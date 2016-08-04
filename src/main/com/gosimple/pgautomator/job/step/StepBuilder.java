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

package com.gosimple.pgautomator.job.step;

import com.gosimple.pgautomator.Config;
import com.gosimple.pgautomator.database.Database;
import com.gosimple.pgautomator.job.Job;
import com.gosimple.pgautomator.job.State;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.LinkedHashMap;

public class StepBuilder
{
    private Job job;
    private int step_id;
    private String step_name;
    private StepType step_type;
    private String database_name;
    private Long step_timeout;
    private Integer success_code;
    private Integer retry_attempts;
    private Long retry_interval;
    private StepAction on_fail_action;
    private Integer on_fail_step_id;
    private StepAction on_success_action;
    private Integer on_success_step_id;
    private String step_command;
    private String database_host;
    private String database_login;
    private String database_pass;
    private String database_auth_query;
    private State email_on;
    private String[] email_to;
    private String email_subject;
    private String email_body;

    public StepBuilder setJob(Job job)
    {
        this.job = job;
        return this;
    }

    public StepBuilder setStepId(int step_id)
    {
        this.step_id = step_id;
        return this;
    }

    public StepBuilder setStepName(String step_name)
    {
        this.step_name = step_name;
        return this;
    }

    public StepBuilder setStepType(StepType step_type)
    {
        this.step_type = step_type;
        return this;
    }

    public StepBuilder setDatabaseName(String database_name)
    {
        this.database_name = database_name;
        return this;
    }

    public StepBuilder setStepTimeout(Long step_timeout)
    {
        this.step_timeout = step_timeout;
        return this;
    }

    public StepBuilder setSuccessCode(Integer success_code)
    {
        this.success_code = success_code;
        return this;
    }

    public StepBuilder setRetryAttempts(Integer retry_attempts)
    {
        this.retry_attempts = retry_attempts;
        return this;
    }

    public StepBuilder setRetryInterval(Long retry_interval)
    {
        this.retry_interval = retry_interval;
        return this;
    }

    public StepBuilder setOnFailAction(StepAction on_fail_action)
    {
        this.on_fail_action = on_fail_action;
        return this;
    }

    public StepBuilder setOnFailStepId(Integer on_fail_step_id)
    {
        this.on_fail_step_id = on_fail_step_id;
        return this;
    }

    public StepBuilder setOnSuccessAction(StepAction on_success_action)
    {
        this.on_success_action = on_success_action;
        return this;
    }

    public StepBuilder setOnSuccessStepId(Integer on_success_step_id)
    {
        this.on_success_step_id = on_success_step_id;
        return this;
    }

    public StepBuilder setStepCommand(String step_command)
    {
        this.step_command = step_command;
        return this;
    }

    public StepBuilder setDatabaseHost(String database_host)
    {
        this.database_host = database_host;
        return this;
    }

    public StepBuilder setDatabaseLogin(String database_login)
    {
        this.database_login = database_login;
        return this;
    }

    public StepBuilder setDatabasePass(String database_pass)
    {
        this.database_pass = database_pass;
        return this;
    }

    public StepBuilder setDatabaseAuthQuery(String database_auth_query)
    {
        this.database_auth_query = database_auth_query;
        return this;
    }

    public StepBuilder setEmailOn(State email_on)
    {
        this.email_on = email_on;
        return this;
    }

    public StepBuilder setEmailTo(String[] email_to)
    {
        this.email_to = email_to;
        return this;
    }

    public StepBuilder setEmailSubject(String email_subject)
    {
        this.email_subject = email_subject;
        return this;
    }

    public StepBuilder setEmailBody(String email_body)
    {
        this.email_body = email_body;
        return this;
    }

    public Step createStep()
    {
        return new Step(job, step_id, step_name, step_type, database_name, step_timeout, success_code, retry_attempts, retry_interval, on_fail_action, on_fail_step_id, on_success_action, on_success_step_id, step_command, database_host, database_login, database_pass, database_auth_query, email_on, email_to, email_subject, email_body);
    }

    /**
     * Returns a list of job steps to
     * @param job
     * @return
     */
    public static LinkedHashMap<Integer, Step> createJobSteps(final Job job)
    {
        Config.INSTANCE.logger.debug("Building steps.");
        LinkedHashMap<Integer, Step> job_step_list = new LinkedHashMap<>();
        final String step_sql = "SELECT * FROM pgautomator.get_steps(?);";
        try (final PreparedStatement statement = Database.INSTANCE.getMainConnection().prepareStatement(step_sql))
        {
            statement.setInt(1, job.getJobId());

            try (final ResultSet resultSet = statement.executeQuery())
            {
                while (resultSet.next())
                {
                    Step job_step = new StepBuilder()
                            .setJob(job)
                            .setStepId(resultSet.getInt("step_id"))
                            .setStepName(resultSet.getString("step_name"))
                            .setStepType(StepType.valueOf(resultSet.getString("step_type")))
                            .setDatabaseName(resultSet.getString("step_database_name"))
                            .setStepTimeout(resultSet.getLong("step_timeout_ms"))
                            .setSuccessCode(resultSet.getInt("step_success_code"))
                            .setRetryAttempts(resultSet.getInt("step_retry_attempts"))
                            .setRetryInterval(resultSet.getLong("step_retry_interval_ms"))
                            .setOnFailAction(StepAction.valueOf(resultSet.getString("step_on_fail_action")))
                            .setOnFailStepId(resultSet.getInt("step_on_fail_step_id"))
                            .setOnSuccessAction(StepAction.valueOf(resultSet.getString("step_on_success_action")))
                            .setOnSuccessStepId(resultSet.getInt("step_on_success_step_id"))
                            .setStepCommand(resultSet.getString("step_command"))
                            .setDatabaseHost(resultSet.getString("step_database_host"))
                            .setDatabaseLogin(resultSet.getString("step_database_login"))
                            .setDatabasePass(resultSet.getString("step_database_pass"))
                            .setDatabaseAuthQuery(resultSet.getString("step_database_auth_query"))
                            .setEmailOn(resultSet.getString("email_on") == null ? null : State.valueOf(resultSet.getString("email_on")))
                            .setEmailTo(resultSet.getArray("email_to") == null ? null : String[].class.cast(resultSet.getArray("email_to").getArray()))
                            .setEmailSubject(resultSet.getString("email_subject"))
                            .setEmailBody(resultSet.getString("email_body"))
                            .createStep();
                    job_step_list.put(job_step.getStepId(), job_step);
                }
            }
        }
        catch (final SQLException e)
        {
            Config.INSTANCE.logger.error("An error occurred getting job steps.");
            Config.INSTANCE.logger.error(e.getMessage());
        }
        return job_step_list;
    }
}