/*
 * Copyright (c) 2016, adamb
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

package com.gosimple.pgautomator.job;

import com.gosimple.pgautomator.database.Database;
import com.gosimple.pgautomator.thread.ThreadFactory;
import com.gosimple.pgautomator.Config;
import com.gosimple.pgautomator.email.EmailUtil;
import com.gosimple.pgautomator.thread.CancellableRunnable;
import com.gosimple.pgautomator.job.step.Step;
import com.gosimple.pgautomator.job.step.StepAction;

import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.*;
import java.util.concurrent.Future;

public class Job implements CancellableRunnable
{
    private final int job_id;
    private int job_log_id;
    private String job_name;
    private State job_state;
    private LinkedHashMap<Integer, Step> step_list;
    private final Map<Step, Future> future_map = new HashMap<>();
    private Long start_time;
    // Timeout setting to abort job if running longer than this value.
    private final Long job_timeout;
    // List of status to send an email on
    private final State email_on;
    // Email to list
    private final String[] email_to;
    // Email subject
    private String email_subject;
    // Email body
    private String email_body;


    public Job(final int job_id, final String job_name, final Long job_timeout, final State email_on, final String[] email_to, final String email_subject, final String email_body, final int job_log_id)
    {
        Config.INSTANCE.logger.debug("Instantiating Job begin.");
        this.job_id = job_id;
        this.job_name = job_name;
        this.job_timeout = job_timeout;
        this.email_on = email_on;
        this.email_to = email_to;
        this.email_subject = email_subject;
        this.email_body = email_body;
        this.job_log_id = job_log_id;
        Config.INSTANCE.logger.debug("Job instantiation complete.");
    }

    /**
     * Gets the next step by index.
     * @param step_id
     * @return the next step_id based on index or null if none.
     */
    private Integer getNextStepId(final Integer step_id)
    {
        ArrayList<Integer> index_list = new ArrayList<>(step_list.keySet());
        if(index_list.contains(step_id + 1))
        {
            return index_list.indexOf(step_id + 1);
        }
        return null;
    }

    /**
     * Executes the step and returns the next step to execute once ready.
     * Will wait until step is done executing to return if necessary, or
     * return as soon as it has submitted for execution if able to run in
     * parallel.
     * @param step_id
     * @return The step id to execute next, or null when no remaining steps.
     */
    private Integer runStep(final Integer step_id) throws InterruptedException
    {
        Step step = step_list.get(step_id);

        future_map.put(step, ThreadFactory.INSTANCE.submitTask(step));

        // If we are able to just go to next step, we can potentially run multiple steps in parallel
        if(step.getOnSuccessAction().equals(StepAction.STEP_NEXT) && step.getOnFailAction().equals(StepAction.STEP_NEXT))
        {
            if (!step.canRunInParallel())
            {
                waitOnRunningJobSteps();
            }

            return getNextStepId(step_id);
        }
        else
        {
            // Wait for the step to finish.
            waitOnRunningJobSteps();

            switch (step.getState())
            {
                case ABORTED:
                case FAILED:
                {
                    switch (step.getOnFailAction())
                    {
                        case STEP_NEXT:
                        {
                            return getNextStepId(step_id);
                        }
                        case STEP_SPECIFIC:
                        {
                            return step.getOnFailStepId();
                        }
                        case QUIT_SUCCEEDED:
                        {
                            job_state = State.SUCCEEDED;
                            return null;
                        }
                        case QUIT_FAILED:
                        {
                            job_state = State.FAILED;
                            return null;
                        }
                    }
                    break;
                }
                case SUCCEEDED:
                {
                    switch (step.getOnSuccessAction())
                    {
                        case STEP_NEXT:
                        {
                            return getNextStepId(step_id);
                        }
                        case STEP_SPECIFIC:
                        {
                            return step.getOnSuccessStepId();
                        }
                        case QUIT_SUCCEEDED:
                        {
                            job_state = State.SUCCEEDED;
                            return null;
                        }
                        case QUIT_FAILED:
                        {
                            job_state = State.FAILED;
                            return null;
                        }
                    }
                    break;
                }
            }
        }

        return null;
    }

    public void run()
    {
        try
        {
            Config.INSTANCE.logger.info("Job id: {} started.", job_id);
            this.start_time = System.currentTimeMillis();
            boolean failed_step = false;
            try
            {
                ArrayList<Integer> index_list = new ArrayList<>(step_list.keySet());
                Integer step_id = index_list.get(0);

                // loop to run every step.
                while (step_id != null)
                {
                    step_id = runStep(step_id);
                }

                // Block until all JobSteps are done.
                waitOnRunningJobSteps();

                // See if any step has failed.
                for (Step tmp_step : step_list.values())
                {
                    if (tmp_step.getState().equals(State.FAILED))
                    {
                        failed_step = true;
                    }
                }
            }
            catch (InterruptedException e)
            {
                job_state = State.ABORTED;
            }

            // Fail if we haven't explicitly set the state as something
            if (job_state == null && failed_step)
            {
                job_state = State.FAILED;
            }
            // Succeed if we haven't explicitly set the state as something
            else if (job_state == null)
            {
                job_state = State.SUCCEEDED;
            }
        }
        catch (Exception e)
        {
            job_state = State.FAILED;
            Config.INSTANCE.logger.error(e.getMessage());
        }

        clearJobAgent();

        // Update the log record with the result
        JobLog.finishLog(job_log_id, job_state);

        if(job_state.equals(email_on))
        {
            // Token replacement
            email_subject = email_subject.replaceAll(Config.INSTANCE.status_token, job_state.name());
            email_body = email_body.replaceAll(Config.INSTANCE.status_token, job_state.name());

            email_subject = email_subject.replaceAll(Config.INSTANCE.job_name_token, job_name);
            email_body = email_body.replaceAll(Config.INSTANCE.job_name_token, job_name);

            // Send email
            EmailUtil.sendEmailFromNoReply(email_to, email_subject, email_body);
        }
        Config.INSTANCE.logger.info("Job id: {} complete.", job_id);
    }

    private void clearJobAgent()
    {
        final String update_job_sql = "SELECT pgautomator.clear_job_executing_agent(?);";
        try (final PreparedStatement update_job_statement = Database.INSTANCE.getMainConnection().prepareStatement(update_job_sql))
        {
            update_job_statement.setInt(1, job_id);
            update_job_statement.execute();
        }
        catch (SQLException e)
        {
            Config.INSTANCE.logger.error(e.getMessage());
        }
    }

    /**
     * Waits on job steps that are running and responds to timeouts.
     * @throws InterruptedException
     */
    private void waitOnRunningJobSteps() throws InterruptedException
    {
        while(submittedJobStepsRunning())
        {
            submittedJobStepTimeout();
            if(isTimedOut())
            {
                cancelTask();
                Thread.currentThread().interrupt();
            }
            Thread.sleep(200);
        }
    }

    /**
     * Check if the job steps already submitted to run are complete.
     * @return
     */
    private boolean submittedJobStepsRunning()
    {
        boolean jobsteps_running = false;
        for (Future<?> future : future_map.values())
        {
            if (!future.isDone())
            {
                jobsteps_running = true;
                break;
            }
        }
        return  jobsteps_running;
    }

    /**
     * Cancels JobSteps which have timed out prior to finishing.
     */
    private void submittedJobStepTimeout()
    {
        for (Step job_step : future_map.keySet())
        {
            final Future<?> future = future_map.get(job_step);
            if(job_step.isTimedOut() && !future.isDone())
            {
                future.cancel(true);
            }
        }
    }

    /**
     * Returns if the job is timed out or not.
     * @return
     */
    public boolean isTimedOut()
    {
        if(null != job_timeout && job_timeout != 0 && null != start_time)
        {
            return System.currentTimeMillis() - start_time > job_timeout;
        }
        else
        {
            return false;
        }
    }

    /**
     * Should stop any long running process the thread was doing to exit gracefully as quickly as possible.
     */
    @Override
    public void cancelTask()
    {
        for (Future<?> future : future_map.values())
        {
            if (!future.isDone())
            {
                future.cancel(true);
            }
        }
    }

    public int getJobId()
    {
        return job_id;
    }

    public int getJobLogId()
    {
        return job_log_id;
    }

    public String getJobName()
    {
        return job_name;
    }

    public void setJobStepList(LinkedHashMap<Integer, Step> step_list)
    {
        this.step_list = step_list;
    }
}
