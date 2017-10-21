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

package com.gosimple.pgautomator;

import com.gosimple.pgautomator.database.Database;
import com.gosimple.pgautomator.job.Job;
import com.gosimple.pgautomator.job.JobBuilder;
import com.gosimple.pgautomator.thread.ThreadFactory;
import com.gosimple.pgautomator.job.State;
import com.gosimple.pgautomator.job.step.StepBuilder;
import org.kohsuke.args4j.CmdLineException;
import org.kohsuke.args4j.CmdLineParser;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Future;

class PGAutomator
{
    private static final Map<Integer, Future<?>> job_future_map = new HashMap<>();
    private static boolean run_cleanup = true;

    public static void main(String[] args)
    {
        boolean set_args = setArguments(args);
        if (!set_args)
        {
            System.exit(-1);
        }

        Config.INSTANCE.logger.info("pgAutomator starting.");

        // Enter main loop
        while (true)
        {
            try
            {
                long start_time = System.currentTimeMillis();
                long tmp_start;
                // Create the agent
                tmp_start = System.currentTimeMillis();
                registerAgent();
                Config.INSTANCE.logger.debug("registerAgent complete. Time (ms): " + String.valueOf(System.currentTimeMillis() - tmp_start));

                // Kill all jobs that had it coming.
                tmp_start = System.currentTimeMillis();
                killJobs();
                Config.INSTANCE.logger.debug("killJobs complete. Time (ms): " + String.valueOf(System.currentTimeMillis() - tmp_start));

                // Run cleanup of zombie jobs.
                tmp_start = System.currentTimeMillis();
                cleanup();
                Config.INSTANCE.logger.debug("cleanup complete. Time (ms): " + String.valueOf(System.currentTimeMillis() - tmp_start));

                // Actually run new jobs.
                tmp_start = System.currentTimeMillis();
                runJobs();
                Config.INSTANCE.logger.debug("runJobs complete. Time (ms): " + String.valueOf(System.currentTimeMillis() - tmp_start));

                Config.INSTANCE.logger.info("Poll complete. Time (ms): " + String.valueOf(System.currentTimeMillis() - start_time));
                // Sleep for the allotted time before starting all over.
                Thread.sleep(Config.INSTANCE.poll_interval);
            }
            catch (final Exception e)
            {
                // If it fails, sleep and try and restart the loop
                Config.INSTANCE.logger.error("Error encountered in the main loop.");
                Config.INSTANCE.logger.error(e.getMessage());
                run_cleanup = true;
                try
                {
                    Thread.sleep(Config.INSTANCE.connection_retry_interval);
                }
                catch (InterruptedException ie)
                {
                    Config.INSTANCE.logger.error(ie.getMessage());
                }
            }
        }
    }

    /**
     * Create the agent and get the id.
     * Only runs if there is not an agent id already.
     *
     * @return
     */
    private static void registerAgent() throws Exception
    {
        try (final PreparedStatement statement = Database.INSTANCE.getMainConnection().prepareStatement("SELECT * FROM pgautomator.register_agent(?);"))
        {
            statement.setString(1, Config.INSTANCE.hostname);
            try (final ResultSet result_set = statement.executeQuery())
            {
                Config.INSTANCE.logger.debug("Registering agent.");

                while (result_set.next())
                {
                    Config.INSTANCE.agent_id = result_set.getInt("agent_id");
                    Config.INSTANCE.poll_interval = Long.class.cast(result_set.getObject("agent_poll_interval_ms"));
                    Config.INSTANCE.smtp_email = String.class.cast(result_set.getObject("smtp_email"));
                    Config.INSTANCE.smtp_port = Integer.class.cast(result_set.getObject("smtp_port"));
                    Config.INSTANCE.smtp_ssl = Boolean.class.cast(result_set.getBoolean("smtp_ssl"));
                    Config.INSTANCE.smtp_user = String.class.cast(result_set.getString("smtp_user"));
                    Config.INSTANCE.smtp_password = String.class.cast(result_set.getString("smtp_password"));
                }
            }
        }
    }

    /**
     * Processes jobs to kill.
     *
     * @return
     */
    private static void killJobs() throws Exception
    {
        try (final PreparedStatement statement = Database.INSTANCE.getMainConnection().prepareStatement("SELECT pgautomator.get_killed_jobs(?);"))
        {
            statement.setInt(1, Config.INSTANCE.agent_id);
            try (final ResultSet result_set = statement.executeQuery())
            {
                Config.INSTANCE.logger.debug("Kill jobs begin.");

                while (result_set.next())
                {
                    final Integer job_id = Integer.class.cast(result_set.getObject(1));
                    if(job_id == null)
                    {
                        return;
                    }
                    if (job_future_map.containsKey(job_id))
                    {
                        Config.INSTANCE.logger.info("Killing job_id: {}.", job_id);
                        job_future_map.get(job_id).cancel(true);
                    }
                    else
                    {
                        Config.INSTANCE.logger.info("Kill request for job_id: {} was submitted, but the job was not running.", job_id);
                    }
                }
            }
        }
    }

    /**
     * Does cleanup and initializes pgAutomator to start running jobs again.
     * Only runs if run_cleanup is true.
     *
     * @return
     */
    private static void cleanup() throws Exception
    {
        if(!run_cleanup)
        {
            Config.INSTANCE.logger.debug("Cleanup unnecessary.");
            return;
        }

        Config.INSTANCE.logger.debug("Running cleanup to clear old data and re-initialize to start processing.");

        final String cleanup_sql = "SELECT pgautomator.zombie_killer()";

        try (final Statement statement = Database.INSTANCE.getMainConnection().createStatement())
        {
            statement.execute(cleanup_sql);
        }

        Config.INSTANCE.logger.debug("Cleanup of completed jobs started.");
        final List<Integer> job_ids_to_remove = new ArrayList<>();
        for (Integer job_id : job_future_map.keySet())
        {
            if (job_future_map.get(job_id).isDone())
            {
                job_ids_to_remove.add(job_id);
            }
        }

        for (Integer job_id : job_ids_to_remove)
        {
            job_future_map.remove(job_id);
        }
        job_ids_to_remove.clear();

        // Set the flag to run the cleanup process to false so this won't run again unless needed
        run_cleanup = false;

        Config.INSTANCE.logger.debug("Successfully cleaned up.");
    }

    /**
     * Executes the jobs that are determined to run on this agent at this point.
     *
     * @throws Exception
     */
    private static void runJobs() throws Exception
    {
        Config.INSTANCE.logger.debug("Running jobs begin.");
        final String get_job_sql = "SELECT * FROM pgautomator.get_jobs(?);";


        try (final PreparedStatement get_job_statement = Database.INSTANCE.getMainConnection().prepareStatement(get_job_sql))
        {
            get_job_statement.setInt(1, Config.INSTANCE.agent_id);
            try (final ResultSet resultSet = get_job_statement.executeQuery())
            {
                while (resultSet.next())
                {
                    final int job_id = resultSet.getInt("job_id");
                    final String job_name = resultSet.getString("job_name");
                    final long job_timeout = resultSet.getLong("job_timeout_ms");
                    final State email_on = resultSet.getString("email_on") == null ? null : State.valueOf(resultSet.getString("email_on"));
                    final String[] email_to = resultSet.getArray("email_to") == null ? null : String[].class.cast(resultSet.getArray("email_to").getArray());
                    final String email_subject = resultSet.getString("email_subject");
                    final String email_body = resultSet.getString("email_body");
                    final Job job = JobBuilder.createJob(job_id, job_name, job_timeout, email_on, email_to, email_subject, email_body);
                    job.setJobStepList(StepBuilder.createJobSteps(job));
                    Config.INSTANCE.logger.debug("Submitting job_id {} for execution.", job_id);
                    job_future_map.put(job_id, ThreadFactory.INSTANCE.submitTask(job));
                }
            }
        }

        Config.INSTANCE.logger.debug("Running jobs complete.");
    }

    /**
     * Sets the arguments passed in from command line.
     * Returns true if successful, false if it encountered an error.
     *
     * @param args
     * @return
     */
    private static boolean setArguments(final String[] args)
    {
        final CmdLineParser parser = new CmdLineParser(Config.INSTANCE);

        try
        {
            parser.parseArgument(args);
        }
        catch (final CmdLineException e)
        {
            Config.INSTANCE.logger.error(e.getMessage());
            parser.printUsage(System.out);
            return false;
        }

        if(Config.INSTANCE.help)
        {
            parser.printUsage(System.out);
            return false;
        }

        if(Config.INSTANCE.version)
        {
            System.out.println("pgAutomator version: " + PGAutomator.class.getPackage().getImplementationVersion());
            return false;
        }

        try
        {
            Config.INSTANCE.hostname = InetAddress.getLocalHost().getHostName();
        }
        catch (final UnknownHostException e)
        {
            Config.INSTANCE.logger.error("Unable to get host name to register.");
            Config.INSTANCE.logger.error(e.getMessage());
            return false;
        }
        return true;
    }
}
