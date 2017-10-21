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

package com.gosimple.pgautomator.job;

import com.gosimple.pgautomator.database.Database;
import com.gosimple.pgautomator.Config;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * @author Adam Brusselback.
 */
public class JobLog
{
    /**
     *
     * @param job_id the job_id that is starting.
     * @return the {@code int} job_log_id that was created in the database
     */
    public static int startLog(final int job_id)
    {
        Config.INSTANCE.logger.debug("Inserting logging and marking job as being worked on.");
        final String log_sql = "SELECT pgautomator.begin_job_log(?)";
        Integer job_log_id = null;
        try (final PreparedStatement log_statement = Database.INSTANCE.getMainConnection().prepareStatement(log_sql))
        {

            log_statement.setInt(1, job_id);
            try (final ResultSet resultSet = log_statement.executeQuery())
            {
                while (resultSet.next())
                {
                    job_log_id = resultSet.getInt(1);
                }
            }
        }
        catch (final SQLException e)
        {
            Config.INSTANCE.logger.error(e.getMessage());
        }

        // If unable to return a job_step_log_id throw an exception.
        if(job_log_id == null)
        {
            throw new IllegalStateException("Unable to return a job log id for an unknown reason.");
        }

        return job_log_id;
    }

    public static void finishLog(final int job_log_id, final State job_state)
    {
        final String log_sql = "SELECT pgautomator.finish_job_log(?, ?::pgautomator.state);";
        try (final PreparedStatement log_statement = Database.INSTANCE.getMainConnection().prepareStatement(log_sql))
        {
            log_statement.setInt(1, job_log_id);
            log_statement.setString(2, job_state.name());
            log_statement.execute();
        }
        catch (SQLException e)
        {
            Config.INSTANCE.logger.error(e.getMessage());
        }
    }
}
