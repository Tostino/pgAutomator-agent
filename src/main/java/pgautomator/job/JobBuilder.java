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

package pgautomator.job;

public class JobBuilder
{
    private Integer job_id;
    private String job_name;
    private Long job_timeout_ms;
    private State email_on;
    private String[] email_to;
    private String email_subject;
    private String email_body;
    private Integer job_log_id;

    public JobBuilder setJobId(Integer job_id)
    {
        this.job_id = job_id;
        return this;
    }

    public JobBuilder setJobName(String job_name)
    {
        this.job_name = job_name;
        return this;
    }

    public void setJobTimeoutMs(Long job_timeout_ms)
    {
        this.job_timeout_ms = job_timeout_ms;
    }

    public void setEmailOn(State email_on)
    {
        this.email_on = email_on;
    }

    public void setEmailTo(String[] email_to)
    {
        this.email_to = email_to;
    }

    public void setEmailSubject(String email_subject)
    {
        this.email_subject = email_subject;
    }

    public void setEmailBody(String email_body)
    {
        this.email_body = email_body;
    }

    public JobBuilder setJobLogId(Integer job_log_id)
    {
        this.job_log_id = job_log_id;
        return this;
    }

    public Job createJob()
    {
        return new Job(job_id, job_name, job_timeout_ms, email_on, email_to, email_subject, email_body, job_log_id);
    }

    public static Job createJob(final int job_id, final String job_name, final Long job_timeout_ms, final State email_on, final String[] email_to, final String email_subject, final String email_body)
    {
        return new JobBuilder().setJobId(job_id).setJobName(job_name).setJobLogId(JobLog.startLog(job_id)).createJob();
    }
}