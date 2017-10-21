/*
 * Copyright (c) 2017, Adam Brusselback
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

package com.gosimple.pgautomator.job.step;


import com.gosimple.pgautomator.database.Database;
import com.gosimple.pgautomator.database.DatabaseAuth;
import com.gosimple.pgautomator.job.Job;
import com.gosimple.pgautomator.Config;
import com.gosimple.pgautomator.email.EmailUtil;
import com.gosimple.pgautomator.job.State;
import com.gosimple.pgautomator.thread.CancellableRunnable;

import java.io.*;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class Step implements CancellableRunnable
{
    private final Job job;
    private final int step_id;
    private final String step_name;
    private final StepType step_type;
    private String step_command;
    // If true, will run in parallel with previous step.
    private final Boolean run_in_parallel = false;
    // Timeout setting to abort job if running longer than this value.
    private final Long step_timeout;
    // Database name
    private final String database_name;
    private final Integer success_code;
    private final Integer retry_attempts;
    private final Long retry_interval;
    private final StepAction on_fail_action;
    private final Integer on_fail_step_id;
    private final StepAction on_success_action;
    private final Integer on_success_step_id;
    // Database host
    private final String database_host;
    // Database login to use
    private final String database_login;
    // Database password to use
    private final String database_pass;
    // Database auth query
    private final String database_auth_query;
    // List of status to send an email on
    private final State email_on;
    // Email to list
    private final String[] email_to;
    // Email subject
    private String email_subject;
    // Email body
    private String email_body;
    // The step log id
    private Integer step_log_id;

    private State step_state;
    private int step_result;
    private String step_output;
    private OSType os_type;

    private Statement running_statement;
    private Process running_process;
    private Long start_time;

    public Step(final Job job, final int step_id, final String step_name, final StepType step_type, final String database_name, final Long step_timeout, final Integer success_code, final Integer retry_attempts, final Long retry_interval, final StepAction on_fail_action, final Integer on_fail_step_id, final StepAction on_success_action, final Integer on_success_step_id, final String step_command, final String database_host, final String database_login, final String database_pass, final String database_auth_query, final State email_on, final String[] email_to, final String email_subject, final String email_body)
    {
        Config.INSTANCE.logger.debug("Step instantiation begin.");
        this.job = job;
        this.step_id = step_id;
        this.step_name = step_name;
        this.step_type = step_type;
        this.database_name = database_name;
        this.step_timeout = step_timeout;
        this.success_code = success_code;
        this.retry_attempts = retry_attempts;
        this.retry_interval = retry_interval;
        this.on_fail_action = on_fail_action;
        this.on_fail_step_id = on_fail_step_id;
        this.on_success_action = on_success_action;
        this.on_success_step_id = on_success_step_id;
        this.step_command = step_command;
        this.database_host = database_host;
        this.database_login = database_login;
        this.database_pass = database_pass;
        this.database_auth_query = database_auth_query;
        this.email_to = email_to;
        this.email_on = email_on;
        this.email_subject = email_subject;
        this.email_body = email_body;
        String os_name = System.getProperty("os.name");
        if (os_name.startsWith("Windows"))
        {
            os_type = OSType.WIN;
        }
        else if (os_name.startsWith("LINUX") || os_name.startsWith("Linux") || os_name.startsWith("Mac"))
        {
            os_type = OSType.NIX;
        }
    }

    public void run()
    {
        this.start_time = System.currentTimeMillis();
        // Insert the job step log and get the id
        this.step_log_id = StepLog.startLog(job.getJobLogId(), step_id);

        // Run the step and retry as necessary
        int current_attempt = 0;
        do
        {
            if (current_attempt != 0)
            {
                try
                {
                    Thread.sleep(retry_interval);
                }
                catch (InterruptedException e)
                {
                    e.printStackTrace();
                }
            }
            runStep();
            current_attempt++;
        }
        while (current_attempt <= retry_attempts && step_state.equals(State.FAILED));


        // Update the job step log record with the result of the job step.
        StepLog.finishLog(step_log_id, step_state, current_attempt - 1, step_result, step_output);

        if(step_state.equals(email_on))
        {
            // Token replacement
            email_subject = email_subject.replaceAll(Config.INSTANCE.status_token, step_state.name());
            email_body = email_body.replaceAll(Config.INSTANCE.status_token, step_state.name());

            email_subject = email_subject.replaceAll(Config.INSTANCE.job_name_token, job.getJobName());
            email_body = email_body.replaceAll(Config.INSTANCE.job_name_token, job.getJobName());

            email_subject = email_subject.replaceAll(Config.INSTANCE.job_step_name_token, step_name);
            email_body = email_body.replaceAll(Config.INSTANCE.job_step_name_token, step_name);

            // Send email
            EmailUtil.sendEmailFromNoReply(email_to, email_subject, email_body);
        }
        Config.INSTANCE.logger.info("Step id: {} complete.", step_id);
    }

    private void runStep()
    {
        switch (step_type)
        {
            case SQL:
            {
                Config.INSTANCE.logger.debug("Executing SQL step: {}", step_id);
                try
                {
                    List<DatabaseAuth> db_auth = new ArrayList<>();

                    // If there is an db_auth query, run it and add all results to the db_auth list
                    if (database_auth_query != null)
                    {
                        try (Connection connection = Database.INSTANCE.getConnection(getHost(), getDatabase()))
                        {
                            try (Statement statement = connection.createStatement())
                            {
                                this.running_statement = statement;
                                try (ResultSet result = statement.executeQuery(database_auth_query))
                                {
                                    while (result.next())
                                    {
                                        db_auth.add(new DatabaseAuth(result.getString(1), result.getString(2)));
                                    }
                                }
                                this.running_statement = null;
                            }
                        }
                    }
                    // If there were explicit credentials passed in, add them to the db_auth list.
                    if (database_login != null || database_pass != null)
                    {
                        db_auth.add(new DatabaseAuth(database_login, database_pass));
                    }
                    // If nothing else was added to the auth list so far, add the configured pgAutomator credentials.
                    if (db_auth.size() == 0)
                    {
                        db_auth.add(new DatabaseAuth(Config.INSTANCE.db_user, Config.INSTANCE.db_password));
                    }

                    for (DatabaseAuth auth : db_auth)
                    {
                        try (Connection connection = Database.INSTANCE.getConnection(getHost(), getDatabase(), auth.getUser(), auth.getPass()))
                        {
                            try (Statement statement = connection.createStatement())
                            {
                                this.running_statement = statement;
                                statement.execute(step_command);
                                this.running_statement = null;
                                step_result = 1;
                                step_state = State.SUCCEEDED;
                            }
                        }
                    }
                }
                catch (final Exception e)
                {
                    step_output = e.getMessage();
                    if (Thread.currentThread().isInterrupted())
                    {
                        step_result = 0;
                        step_state = State.ABORTED;
                    }
                    else
                    {
                        step_result = -1;
                        step_state = State.FAILED;
                    }
                }
                break;
            }
            case BATCH:
            {
                Config.INSTANCE.logger.debug("Executing Batch step: {}", step_id);

                try
                {
                    // Replace line breaks for each OS type.
                    step_command = step_command.replaceAll("\\r\\n|\\r|\\n", System.getProperty("line.separator"));

                    final String fileExtension;
                    if (os_type.equals(OSType.WIN))
                    {
                        fileExtension = ".bat";
                    }
                    else
                    {
                        fileExtension = ".sh";
                    }

                    final File tmp_file_script = File.createTempFile("pga_", fileExtension, null);
                    tmp_file_script.deleteOnExit();
                    tmp_file_script.setWritable(true);
                    tmp_file_script.setExecutable(true);


                    final BufferedWriter buffered_writer = new BufferedWriter(new FileWriter(tmp_file_script));
                    buffered_writer.write(this.step_command);
                    buffered_writer.close();

                    final ProcessBuilder process_builder = new ProcessBuilder(tmp_file_script.getAbsolutePath());
                    this.running_process = process_builder.start();
                    this.running_process.waitFor();


                    final BufferedReader buffered_reader_out = new BufferedReader(new InputStreamReader(this.running_process.getInputStream()));
                    final BufferedReader buffered_reader_error = new BufferedReader(new InputStreamReader(this.running_process.getErrorStream()));
                    final StringBuilder string_builder = new StringBuilder();
                    String line;
                    // Get normal output.
                    while ((line = buffered_reader_out.readLine()) != null)
                    {
                        string_builder.append(line);
                        string_builder.append(System.getProperty("line.separator"));
                    }
                    // Get error output.
                    while ((line = buffered_reader_error.readLine()) != null)
                    {
                        string_builder.append(line);
                        string_builder.append(System.getProperty("line.separator"));
                    }

                    tmp_file_script.delete();
                    this.step_output = string_builder.toString();
                    this.step_result = running_process.exitValue();
                    if (success_code.equals(step_result))
                    {
                        step_state = State.SUCCEEDED;
                    }
                    else
                    {
                        step_state = State.FAILED;
                    }
                }
                catch (InterruptedException e)
                {
                    this.step_result = running_process.exitValue();
                    this.step_state = State.ABORTED;
                }
                catch (Exception e)
                {
                    this.step_result = running_process.exitValue();
                    this.step_state = State.FAILED;
                }
                finally
                {
                    this.running_process = null;
                }
                break;
            }
        }
    }

    private String getHost()
    {
        if(database_host != null)
        {
            return database_host;
        }
        else
        {
            return Config.INSTANCE.db_host;
        }
    }

    private String getDatabase()
    {
        return database_name;
    }

    /**
     * Returns if the job is timed out or not.
     * @return
     */
    public boolean isTimedOut()
    {
        if(null != step_timeout && step_timeout != 0 && null != start_time)
        {
            return System.currentTimeMillis() - start_time > step_timeout;
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
        switch (step_type)
        {
            case SQL:
                if (running_statement != null)
                {
                    try
                    {
                        running_statement.cancel();
                    }
                    catch (SQLException e)
                    {
                        Config.INSTANCE.logger.error(e.getMessage());
                    }
                }
                break;
            case BATCH:
                if (running_process != null && running_process.isAlive())
                {
                    running_process.destroy();
                }
                break;
        }

    }

    /**
     * Gets the step_id.
     * @return the step_id.
     */
    public Integer getStepId()
    {
        return step_id;
    }

    /**
     * Gets the State of the Step.
     *
     * @return
     */
    public State getState()
    {
        return step_state;
    }

    /**
     * Returns if the job can run in parallel with the previous step.
     * @return
     */
    public Boolean canRunInParallel()
    {
        return this.run_in_parallel;
    }

    /**
     * Returns the step id to run on success.
     * @return
     */
    public Integer getOnSuccessStepId()
    {
        return this.on_success_step_id;
    }

    /**
     * Returns the step id to run on failure.
     * @return
     */
    public Integer getOnFailStepId()
    {
        return this.on_fail_step_id;
    }

    /**
     * Returns the action to perform on success.
     * @return
     */
    public StepAction getOnSuccessAction()
    {
        return this.on_success_action;
    }

    /**
     * Returns the action to perform on fail.
     * @return
     */
    public StepAction getOnFailAction()
    {
        return this.on_fail_action;
    }
}
