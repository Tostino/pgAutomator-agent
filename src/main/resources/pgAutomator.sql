/*
// pgAutomator - The most advanced PostgreSQL job scheduler.
// 
// Copyright (C) 2016 Adam Brusselback
// This software is released under the PostgreSQL Licence
//
// pgautomator.sql - pgAutomator tables, views and functions
//
*/

DROP SCHEMA IF EXISTS pgautomator CASCADE;

BEGIN TRANSACTION;


CREATE SCHEMA pgautomator;
COMMENT ON SCHEMA pgautomator IS 'pgAutomator system tables';


CREATE TYPE pgautomator.step_type AS ENUM
   ('SQL',
    'BATCH');

CREATE TYPE pgautomator.state AS ENUM
   ('RUNNING',
    'FAILED',
    'SUCCEEDED',
    'ABORTED');
    
CREATE TYPE pgautomator.step_action AS ENUM
   ('STEP_NEXT',
    'STEP_SPECIFIC',
    'QUIT_SUCCEEDED',
    'QUIT_FAILED');

/**
* No support for ON_IDLE or ON_TRIGGER_FILE yet, will add that soon.
**/
CREATE TYPE pgautomator.schedule_type AS ENUM
   ('DATE',
    'ON_IDLE',
    'ON_TRIGGER_FILE');

CREATE TYPE pgautomator.day_of_week AS ENUM
   ('SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY');

CREATE TYPE pgautomator.timing AS ENUM
   ('FIRST',
    'SECOND',
    'THIRD',
    'FOURTH',
    'LAST');

CREATE TABLE pgautomator.agent (
agent_id serial NOT NULL PRIMARY KEY,
agent_identifier text NOT NULL,
agent_description text,
agent_poll_interval interval NOT NULL,
agent_registered timestamptz NOT NULL,
agent_last_poll timestamptz,
agent_pid int,
CONSTRAINT agent_unique UNIQUE (agent_identifier),
CONSTRAINT agent_min_poll_interval CHECK (agent_poll_interval >= '1 second'::interval)
);
COMMENT ON TABLE pgautomator.agent IS 'List of agents registered.';


CREATE TABLE pgautomator.agent_smtp (
agent_id int NOT NULL UNIQUE REFERENCES pgautomator.agent (agent_id),
smtp_email text NOT NULL,
smtp_host text NOT NULL,
smtp_port int NOT NULL,
smtp_ssl boolean NOT NULL,
smtp_user text,
smtp_password text
);
COMMENT ON TABLE pgautomator.agent_smtp IS 'SMTP info to use for each agent.';


CREATE TABLE pgautomator.job_category (
job_category_id serial NOT NULL PRIMARY KEY,
category text NOT NULL,
CONSTRAINT job_category_unique UNIQUE (category)
);
COMMENT ON TABLE pgautomator.job_category IS 'Ways to categorize a Job.';

INSERT INTO pgautomator.job_category (category) VALUES ('Routine Maintenance');
INSERT INTO pgautomator.job_category (category) VALUES ('Data Import');
INSERT INTO pgautomator.job_category (category) VALUES ('Data Export');
INSERT INTO pgautomator.job_category (category) VALUES ('Data Summarisation');
INSERT INTO pgautomator.job_category (category) VALUES ('Miscellaneous');


CREATE TABLE pgautomator.job (
job_id serial NOT NULL PRIMARY KEY,
job_category_id int NOT NULL REFERENCES pgautomator.job_category (job_category_id),
job_name text NOT NULL,
job_description text,
job_enabled boolean NOT NULL,
job_timeout interval,
job_assigned_agent_id int REFERENCES pgautomator.agent (agent_id),
job_created timestamptz NOT NULL,
job_modified timestamptz NOT NULL,
job_next_run_schedule_id int,
job_next_run timestamptz,
job_executing_agent_id int REFERENCES pgautomator.agent (agent_id)
);
COMMENT ON TABLE pgautomator.job IS 'Job is the container for schedules and steps';

CREATE TABLE pgautomator.job_email (
job_id int NOT NULL UNIQUE REFERENCES pgautomator.job (job_id),
email_on pgautomator.state NOT NULL,
email_to text[] NOT NULL,
email_subject text NOT NULL,
email_body text NOT NULL
);
COMMENT ON TABLE pgautomator.job_email IS 'If email is setup for this job, this table has the info.';

CREATE TABLE pgautomator.job_kill (
job_id int NOT NULL UNIQUE REFERENCES pgautomator.job (job_id)
);
COMMENT ON TABLE pgautomator.job_kill IS 'Contains job ids that need to be killed.';


CREATE TABLE pgautomator.step (
step_id serial NOT NULL PRIMARY KEY,
job_id int NOT NULL REFERENCES pgautomator.job (job_id) ON DELETE CASCADE,
step_name text NOT NULL,
step_description text,
step_index integer NOT NULL,
step_enabled boolean NOT NULL,
step_type pgautomator.step_type NOT NULL,
step_database_name text,
step_timeout interval,
step_success_code int,
step_retry_attempts integer NOT NULL,
step_retry_interval interval NOT NULL,
step_on_fail_action pgautomator.step_action NOT NULL,
step_on_fail_step_id int REFERENCES pgautomator.step (step_id),
step_on_success_action pgautomator.step_action NOT NULL,
step_on_success_step_id int REFERENCES pgautomator.step (step_id),
step_command text NOT NULL,
CONSTRAINT step_index_unique UNIQUE (step_id, step_index),
CONSTRAINT check_step_type CHECK ((step_type = 'SQL' AND step_success_code IS NULL AND step_database_name IS NOT NULL) OR (step_type = 'BATCH' AND step_success_code IS NOT NULL AND step_database_name IS NULL)),
CONSTRAINT check_step_on_fail CHECK ((step_on_fail_action = 'STEP_SPECIFIC' AND step_on_fail_step_id IS NOT NULL) OR (step_on_fail_action <> 'STEP_SPECIFIC' AND step_on_fail_step_id IS NULL)),
CONSTRAINT check_step_on_success CHECK ((step_on_success_action = 'STEP_SPECIFIC' AND step_on_success_step_id IS NOT NULL) OR (step_on_success_action <> 'STEP_SPECIFIC' AND step_on_success_step_id IS NULL))
);
COMMENT ON TABLE pgautomator.step IS 'Step to be executed.';

CREATE TABLE pgautomator.step_email (
step_id int NOT NULL UNIQUE REFERENCES pgautomator.step (step_id),
email_on pgautomator.state NOT NULL,
email_to text[] NOT NULL,
email_subject text NOT NULL,
email_body text NOT NULL
);
COMMENT ON TABLE pgautomator.step_email IS 'If email is setup for this step, this table has the info.';

CREATE TABLE pgautomator.step_connection (
step_id int NOT NULL UNIQUE REFERENCES pgautomator.step (step_id),
step_database_host text NOT NULL,
step_database_login text NOT NULL,
step_database_pass text,
step_database_auth_query text
);
COMMENT ON TABLE pgautomator.step_connection IS 'Connection info for the database for a step';


CREATE TABLE pgautomator.job_log (
job_log_id serial NOT NULL PRIMARY KEY,
job_id int NOT NULL REFERENCES pgautomator.job (job_id),
agent_id int NOT NULL REFERENCES pgautomator.agent (agent_id),
schedule_id int,
job_log_state pgautomator.state NOT NULL,
job_log_start timestamptz NOT NULL,
job_log_duration interval
);
CREATE UNIQUE INDEX job_log_running_unique ON pgautomator.job_log USING btree (job_id) WHERE job_log_state = 'RUNNING';
COMMENT ON TABLE pgautomator.job_log IS 'Log for the job itself';


CREATE TABLE pgautomator.step_log (
step_log_id serial NOT NULL PRIMARY KEY,
job_log_id int NOT NULL REFERENCES pgautomator.job_log (job_log_id),
step_id int NOT NULL REFERENCES pgautomator.step (step_id),
step_log_state pgautomator.state NOT NULL,
step_log_start timestamptz NOT NULL,
step_log_duration interval,
step_log_exit_code int,
step_log_retries int,
step_log_message text
);
COMMENT ON TABLE pgautomator.step_log IS 'Log for steps within a job';


CREATE TABLE pgautomator.schedule_type_once (
schedule_type_once_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
schedule_date date NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_type_once IS 'One time schedule info';

CREATE TABLE pgautomator.schedule_type_daily (
schedule_type_daily_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
schedule_interval int NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_type_daily IS 'Daily schedule info';

CREATE TABLE pgautomator.schedule_type_weekly (
schedule_type_weekly_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
day_of_week pgautomator.day_of_week[] NOT NULL,
schedule_interval int NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_type_weekly IS 'Weekly schedule info';

CREATE TABLE pgautomator.schedule_type_monthly (
schedule_type_monthly_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
day_of_month int NOT NULL,
schedule_interval int NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_type_monthly IS 'Monthly schedule info';

CREATE TABLE pgautomator.schedule_type_monthly_relative (
schedule_type_monthly_relative_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
timing pgautomator.timing NOT NULL,
day_of_week pgautomator.day_of_week NOT NULL,
schedule_interval int NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_type_monthly_relative IS 'Monthly - Relative schedule info';

CREATE TABLE pgautomator.schedule_sub_once (
schedule_sub_once_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
schedule_time timetz NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_sub_once IS 'Sub schedule info for single runs';

CREATE TABLE pgautomator.schedule_sub_every (
schedule_sub_every_id serial NOT NULL PRIMARY KEY,
schedule_id int NOT NULL,
start_at timetz NOT NULL,
end_at timetz NOT NULL,
schedule_interval interval NOT NULL
);
COMMENT ON TABLE pgautomator.schedule_sub_every IS 'Sub schedule info for multiple runs';

CREATE TABLE pgautomator.schedule (
schedule_id serial NOT NULL PRIMARY KEY,
schedule_name text NOT NULL,
schedule_type pgautomator.schedule_type NOT NULL,
schedule_type_once_id int REFERENCES pgautomator.schedule_type_once (schedule_type_once_id) DEFERRABLE INITIALLY DEFERRED,
schedule_type_daily_id int REFERENCES pgautomator.schedule_type_daily (schedule_type_daily_id) DEFERRABLE INITIALLY DEFERRED,
schedule_type_weekly_id int REFERENCES pgautomator.schedule_type_weekly (schedule_type_weekly_id) DEFERRABLE INITIALLY DEFERRED,
schedule_type_monthly_id int REFERENCES pgautomator.schedule_type_monthly (schedule_type_monthly_id) DEFERRABLE INITIALLY DEFERRED,
schedule_type_monthly_relative_id int REFERENCES pgautomator.schedule_type_monthly_relative (schedule_type_monthly_relative_id) DEFERRABLE INITIALLY DEFERRED,
schedule_sub_once_id int REFERENCES pgautomator.schedule_sub_once (schedule_sub_once_id) DEFERRABLE INITIALLY DEFERRED,
schedule_sub_every_id int REFERENCES pgautomator.schedule_sub_every (schedule_sub_every_id) DEFERRABLE INITIALLY DEFERRED,
schedule_start_date date NOT NULL,
schedule_end_date date,
schedule_enabled boolean NOT NULL,
CONSTRAINT check_schedule_type CHECK ((
CASE 
    WHEN schedule_type = 'DATE' 
    THEN schedule_type_once_id IS NOT NULL 
        OR schedule_type_daily_id IS NOT NULL
        OR schedule_type_daily_id IS NOT NULL
        OR schedule_type_weekly_id IS NOT NULL
        OR schedule_type_monthly_id IS NOT NULL
        OR schedule_type_monthly_relative_id IS NOT NULL
    ELSE true
END
)),
CONSTRAINT check_schedule_type_one_not_null CHECK ((
CASE
    WHEN schedule_type_once_id IS NULL THEN 0
    ELSE 1
END +
CASE
    WHEN schedule_type_daily_id IS NULL THEN 0
    ELSE 1
END +
CASE
    WHEN schedule_type_weekly_id IS NULL THEN 0
    ELSE 1
END +
CASE
    WHEN schedule_type_monthly_id IS NULL THEN 0
    ELSE 1
END +
CASE
    WHEN schedule_type_monthly_relative_id IS NULL THEN 0
    ELSE 1
END) = (CASE WHEN schedule_type IN ('DATE') THEN 1 WHEN schedule_type IN ('ON_IDLE', 'ON_TRIGGER_FILE') THEN 0 END)
),
CONSTRAINT check_schedule_sub CHECK ((
CASE
    WHEN schedule_sub_once_id IS NULL THEN 0
    ELSE 1
END +
CASE
    WHEN schedule_sub_every_id IS NULL THEN 0
    ELSE 1
END) = (CASE WHEN schedule_type IN ('DATE') THEN 1 WHEN schedule_type IN ('ON_IDLE', 'ON_TRIGGER_FILE') THEN 0 END)
)
);
COMMENT ON TABLE pgautomator.schedule IS 'Schedule table.';



ALTER TABLE pgautomator.schedule_type_once ADD CONSTRAINT schedule_type_once_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE pgautomator.schedule_type_daily ADD CONSTRAINT schedule_type_daily_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE pgautomator.schedule_type_weekly ADD CONSTRAINT schedule_type_weekly_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE pgautomator.schedule_type_monthly ADD CONSTRAINT schedule_type_monthly_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE pgautomator.schedule_type_monthly_relative ADD CONSTRAINT schedule_type_monthly_relative_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE pgautomator.schedule_type_once ADD CONSTRAINT schedule_sub_once_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE pgautomator.schedule_sub_every ADD CONSTRAINT schedule_sub_every_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE pgautomator.job ADD CONSTRAINT job_job_next_run_schedule_id_fkey FOREIGN KEY (job_next_run_schedule_id) REFERENCES pgautomator.schedule (schedule_id);
ALTER TABLE pgautomator.job_log ADD CONSTRAINT job_log_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES pgautomator.schedule (schedule_id);



CREATE TABLE pgautomator.job_schedule (
job_id int NOT NULL REFERENCES pgautomator.job (job_id),
schedule_id int NOT NULL REFERENCES pgautomator.schedule (schedule_id),
CONSTRAINT job_schedule_pkey PRIMARY KEY (job_id, schedule_id)
);
COMMENT ON TABLE pgautomator.job_schedule IS 'Assigns a job to run on a specific schedule.';


CREATE OR REPLACE VIEW pgautomator.agent_active AS
SELECT agent_id
FROM pgautomator.agent
WHERE agent_last_poll + (agent_poll_interval * 3) >= now();
COMMENT ON VIEW pgautomator.agent_active IS 'View of agents which have been polled within the last three times they should have polled. If they have not polled for > poll interval * 3 then we consider the agent not active.';


CREATE FUNCTION pgautomator.last_day_of_month(_date date) 
RETURNS date AS
$BODY$
	SELECT (date_trunc('month', _date) + INTERVAL '1' MONTH - INTERVAL '1' DAY)::date;
$BODY$
LANGUAGE sql IMMUTABLE;
COMMENT ON FUNCTION pgautomator.last_day_of_month(date) IS 'Returns the last day of the month for the date passed in.';

CREATE MATERIALIZED VIEW pgautomator.dim_date AS 
 SELECT dim_date.date,
    dim_date.year,
    dim_date.month,
    dim_date.day_of_month,
    dim_date.day_of_year,
    dim_date.day_of_week,
    dim_date.week_of_month,
    dim_date.weekend_ind,
    dim_date.current_week_start,
    dim_date.current_week_end,
    dim_date.month_start,
    dim_date.month_end,
    dim_date.day_of_week_occurances,
    CASE 
    WHEN dim_date.day_of_week_occurances = 1 THEN 'FIRST'
    WHEN dim_date.day_of_week_occurances = 2 THEN 'SECOND'
    WHEN dim_date.day_of_week_occurances = 3 THEN 'THIRD'
    WHEN dim_date.day_of_week_occurances = 4 THEN 'FOURTH'
    WHEN max(dim_date.day_of_week_occurances) OVER (PARTITION BY dim_date.year, dim_date.month, dim_date.day_of_week) = dim_date.day_of_week_occurances THEN 'LAST'
    END::pgautomator.timing timing
   FROM ( SELECT x.date,
            x.year,
            x.month,
            x.day_of_month,
            x.day_of_year,
            x.day_of_week,
            x.week_of_month,
            x.weekend_ind,
            x.current_week_start,
            x.current_week_end,
            x.month_start,
            x.month_end,
            dense_rank() OVER (PARTITION BY x.year, x.month, x.day_of_week ORDER BY x.date) AS day_of_week_occurances
           FROM ( SELECT t.datum AS date,
                    date_part('year'::text, t.datum)::integer AS year,
                    date_part('month'::text, t.datum)::integer AS month,
                    date_part('day'::text, t.datum)::integer AS day_of_month,
                    date_part('doy'::text, t.datum)::integer AS day_of_year,
                        CASE date_part('dow'::text, t.datum)::integer
                            WHEN 0 THEN 'SUNDAY'::text
                            WHEN 1 THEN 'MONDAY'::text
                            WHEN 2 THEN 'TUESDAY'::text
                            WHEN 3 THEN 'WEDNESDAY'::text
                            WHEN 4 THEN 'THURSDAY'::text
                            WHEN 5 THEN 'FRIDAY'::text
                            WHEN 6 THEN 'SATURDAY'::text
                            ELSE NULL::text
                        END::pgautomator.day_of_week AS day_of_week,
                    dense_rank() OVER (PARTITION BY (date_part('year'::text, t.datum)::integer), (date_part('month'::text, t.datum)::integer) ORDER BY (date_trunc('week'::text, t.datum::timestamp with time zone) - '1 day'::interval day))::integer AS week_of_month,
                        CASE
                            WHEN date_part('isodow'::text, t.datum) = ANY (ARRAY[6::double precision, 7::double precision]) THEN true
                            ELSE false
                        END AS weekend_ind,
                    (date_trunc('week'::text, t.datum::timestamp with time zone) - '1 day'::interval day)::date AS current_week_start,
                    (date_trunc('week'::text, t.datum::timestamp with time zone) - '1 day'::interval day + '7 days'::interval day)::date AS current_week_end,
                    date_trunc('month'::text, t.datum::timestamp with time zone)::date AS month_start,
                    (date_trunc('month'::text, t.datum::timestamp with time zone) + '1 mon'::interval month - '1 day'::interval day)::date AS month_end
                   FROM ( SELECT datum.datum::date AS datum
                           FROM generate_series(now()::date::timestamp with time zone, (now()::date::timestamp with time zone + '1 years'::interval - '1 day'::interval), '1 day'::interval) datum(datum)) t) x) dim_date
  ORDER BY dim_date.date
WITH DATA;
COMMENT ON MATERIALIZED VIEW pgautomator.dim_date IS 'View help with scheduling based on properties of a date.';




CREATE OR REPLACE FUNCTION pgautomator.schema_version() RETURNS int AS 
$$
	SELECT 1;
$$ 
LANGUAGE sql IMMUTABLE;
COMMENT ON FUNCTION pgautomator.schema_version() IS 'Returns the schema version for pgAutomator.';

CREATE OR REPLACE FUNCTION pgautomator.get_time_series(
    _schedule_time time with time zone,
    _start_at time with time zone,
    _end_at time with time zone,
    _interval interval)
  RETURNS SETOF time with time zone AS
$BODY$
BEGIN
	IF _schedule_time IS NOT NULL
	THEN
		RETURN QUERY SELECT _schedule_time as next_run_time;
	ELSE 
		RETURN QUERY
		SELECT generate_series::timetz as next_run_time 
		FROM generate_series(now()::date + _start_at, now()::date + _end_at, _interval);
	END IF;
	
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION pgautomator.get_time_series(time with time zone, time with time zone, time with time zone, interval) IS 'Returns a set of timetz representing the times that this job should run throughout the day.';



CREATE OR REPLACE FUNCTION pgautomator.set_job_next_run()
  RETURNS void AS
$BODY$
BEGIN

CREATE TEMPORARY TABLE job_next_run (
job_id int NOT NULL,
schedule_id int,
next_run timestamptz
);

/**
* Insert into temp table where the job isn't currently running, the job is 
* active, the schedule is active (time and boolean), and the next run is in the past.
**/
INSERT INTO job_next_run (job_id, schedule_id)
SELECT job.job_id, schedule.schedule_id
FROM pgautomator.job_schedule
INNER JOIN pgautomator.job
USING (job_id)
INNER JOIN pgautomator.schedule
USING (schedule_id)
WHERE true
AND schedule.schedule_enabled = true
AND job.job_enabled = true
AND job.job_executing_agent_id IS NULL
AND (job.job_next_run < now() OR job.job_next_run IS NULL);

IF (SELECT count(1) FROM job_next_run) = 0
THEN
	DROP TABLE IF EXISTS job_next_run;
	RETURN;
END IF;

ANALYZE job_next_run;

/**
* Update temp table date for schedule_type_once
**/
UPDATE job_next_run
SET next_run = u.next_run_date + u.next_run_time
FROM (
	SELECT 
	job_next_run.job_id
	, schedule.schedule_id
	, schedule_type_once.schedule_date as next_run_date
	, pgautomator.get_time_series(schedule_sub_once.schedule_time, schedule_sub_every.start_at, schedule_sub_every.end_at, schedule_sub_every.schedule_interval) as next_run_time
	FROM job_next_run
	INNER JOIN pgautomator.job_schedule
	ON job_next_run.job_id = job_schedule.job_id
	AND job_next_run.schedule_id = job_schedule.schedule_id
	INNER JOIN pgautomator.schedule
	ON schedule.schedule_id = job_schedule.schedule_id
	INNER JOIN pgautomator.schedule_type_once
	ON schedule_type_once.schedule_type_once_id = schedule.schedule_type_once_id
	LEFT JOIN pgautomator.schedule_sub_once
	ON schedule_sub_once.schedule_sub_once_id = schedule.schedule_sub_once_id
	LEFT JOIN pgautomator.schedule_sub_every
	ON schedule_sub_every.schedule_sub_every_id = schedule.schedule_sub_every_id
	WHERE true
) u
WHERE true
AND u.next_run_date + u.next_run_time >= now()::date
AND job_next_run.job_id = u.job_id
AND job_next_run.schedule_id = u.schedule_id;


/**
* Update temp table date for schedule_type_daily
**/
UPDATE job_next_run
SET next_run = u.next_run
FROM (
	SELECT 
	t.job_id
	, t.schedule_id
	, min(t.next_run_date + t.next_run_time) AS next_run
	FROM (
		SELECT 
		t2.job_id
		, t2.schedule_id
		, t2.next_run_date
		, pgautomator.get_time_series(t2.schedule_time, t2.start_at, t2.end_at, t2.schedule_interval) as next_run_time
		FROM (
			SELECT job_next_run.job_id
			, schedule.schedule_id
			, generate_series(schedule.schedule_start_date, now()::date + (schedule_type_daily.schedule_interval || ' days')::interval, (schedule_type_daily.schedule_interval || ' days')::interval)::date as next_run_date
			, schedule_sub_once.schedule_time
			, schedule_sub_every.start_at
			, schedule_sub_every.end_at
			, schedule_sub_every.schedule_interval
			FROM job_next_run
			INNER JOIN pgautomator.job_schedule
			ON job_next_run.job_id = job_schedule.job_id
			AND job_next_run.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule
			ON schedule.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule_type_daily
			ON schedule_type_daily.schedule_type_daily_id = schedule.schedule_type_daily_id
			LEFT JOIN pgautomator.schedule_sub_once
			ON schedule_sub_once.schedule_sub_once_id = schedule.schedule_sub_once_id
			LEFT JOIN pgautomator.schedule_sub_every
			ON schedule_sub_every.schedule_sub_every_id = schedule.schedule_sub_every_id
		) t2
		WHERE true
	) t
	WHERE true
	AND t.next_run_date + t.next_run_time >= now()
	GROUP BY t.job_id, t.schedule_id
) u
WHERE true
AND job_next_run.job_id = u.job_id
AND job_next_run.schedule_id = u.schedule_id;


/**
* Update temp table date for schedule_type_weekly
**/
UPDATE job_next_run
SET next_run = u.next_run
FROM (
	SELECT 
	t.job_id
	, t.schedule_id
	, min(t.next_run_date + t.next_run_time) as next_run
	FROM (
		SELECT 
		t2.job_id
		, t2.schedule_id
		, generate_series(dim_date.current_week_start, dim_date.current_week_end, '1 day'::interval)::date as next_run_date
		, t2.next_run_time
		, t2.day_of_week
		FROM (
			SELECT job_next_run.job_id
			, schedule.schedule_id
			, generate_series(schedule.schedule_start_date, now()::date + (schedule_type_weekly.schedule_interval || ' weeks')::interval, (schedule_type_weekly.schedule_interval || ' week')::interval)::date as week_start_date
			, pgautomator.get_time_series(schedule_sub_once.schedule_time, schedule_sub_every.start_at, schedule_sub_every.end_at, schedule_sub_every.schedule_interval) as next_run_time
			, schedule_type_weekly.day_of_week
			FROM job_next_run
			INNER JOIN pgautomator.job_schedule
			ON job_next_run.job_id = job_schedule.job_id
			AND job_next_run.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule
			ON schedule.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule_type_weekly
			ON schedule_type_weekly.schedule_type_weekly_id = schedule.schedule_type_weekly_id
			LEFT JOIN pgautomator.schedule_sub_once
			ON schedule_sub_once.schedule_sub_once_id = schedule.schedule_sub_once_id
			LEFT JOIN pgautomator.schedule_sub_every
			ON schedule_sub_every.schedule_sub_every_id = schedule.schedule_sub_every_id
			WHERE true
		) t2
		INNER JOIN pgautomator.dim_date
		ON t2.week_start_date = dim_date.date
	) t
	INNER JOIN pgautomator.dim_date
	ON t.next_run_date = dim_date.date
	WHERE true
	AND t.next_run_date + t.next_run_time >= now()
	AND dim_date.day_of_week = ANY(t.day_of_week)
	GROUP BY t.job_id, t.schedule_id
) u
WHERE true
AND job_next_run.job_id = u.job_id
AND job_next_run.schedule_id = u.schedule_id;


/**
* Update temp table date for schedule_type_monthly
**/
UPDATE job_next_run
SET next_run = u.next_run
FROM (
	SELECT 
	t.job_id
	, t.schedule_id
	, min(t.next_run_date + t.next_run_time) as next_run
	FROM (
		SELECT 
		t2.job_id
		, t2.schedule_id
		, generate_series(dim_date.month_start, dim_date.month_end, '1 day'::interval)::date as next_run_date
		, t2.next_run_time
		, t2.day_of_month
		FROM (
			SELECT job_next_run.job_id
			, schedule.schedule_id
			, generate_series(schedule.schedule_start_date, now()::date + (schedule_type_monthly.schedule_interval || ' months')::interval, (schedule_type_monthly.schedule_interval || ' months')::interval)::date as month_start_date
			, pgautomator.get_time_series(schedule_sub_once.schedule_time, schedule_sub_every.start_at, schedule_sub_every.end_at, schedule_sub_every.schedule_interval) as next_run_time
			, schedule_type_monthly.day_of_month
			FROM job_next_run
			INNER JOIN pgautomator.job_schedule
			ON job_next_run.job_id = job_schedule.job_id
			AND job_next_run.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule
			ON schedule.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule_type_monthly
			ON schedule_type_monthly.schedule_type_monthly_id = schedule.schedule_type_monthly_id
			LEFT JOIN pgautomator.schedule_sub_once
			ON schedule_sub_once.schedule_sub_once_id = schedule.schedule_sub_once_id
			LEFT JOIN pgautomator.schedule_sub_every
			ON schedule_sub_every.schedule_sub_every_id = schedule.schedule_sub_every_id
			WHERE true
		) t2
		INNER JOIN pgautomator.dim_date
		ON t2.month_start_date = dim_date.date
	) t
	INNER JOIN pgautomator.dim_date
	ON t.next_run_date = dim_date.date
	WHERE true
	AND t.next_run_date + t.next_run_time >= now()
	AND dim_date.day_of_month = t.day_of_month
	GROUP BY t.job_id, t.schedule_id
) u
WHERE true
AND job_next_run.job_id = u.job_id
AND job_next_run.schedule_id = u.schedule_id;

/**
* Update temp table date for schedule_type_monthly_relative
**/
UPDATE job_next_run
SET next_run = u.next_run
FROM (
	SELECT 
	t.job_id
	, t.schedule_id
	, min(t.next_run_date + t.next_run_time) as next_run
	FROM (
		SELECT 
		t2.job_id
		, t2.schedule_id
		, generate_series(dim_date.month_start, dim_date.month_end, '1 day'::interval)::date as next_run_date
		, t2.next_run_time
		, t2.timing
		, t2.day_of_week
		FROM (
			SELECT job_next_run.job_id
			, schedule.schedule_id
			, generate_series(schedule.schedule_start_date, now()::date + (schedule_type_monthly_relative.schedule_interval || ' months')::interval, (schedule_type_monthly_relative.schedule_interval || ' months')::interval)::date as month_start_date
			, pgautomator.get_time_series(schedule_sub_once.schedule_time, schedule_sub_every.start_at, schedule_sub_every.end_at, schedule_sub_every.schedule_interval) as next_run_time
			, schedule_type_monthly_relative.timing
			, schedule_type_monthly_relative.day_of_week
			FROM job_next_run
			INNER JOIN pgautomator.job_schedule
			ON job_next_run.job_id = job_schedule.job_id
			AND job_next_run.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule
			ON schedule.schedule_id = job_schedule.schedule_id
			INNER JOIN pgautomator.schedule_type_monthly_relative
			ON schedule_type_monthly_relative.schedule_type_monthly_relative_id = schedule.schedule_type_monthly_relative_id
			LEFT JOIN pgautomator.schedule_sub_once
			ON schedule_sub_once.schedule_sub_once_id = schedule.schedule_sub_once_id
			LEFT JOIN pgautomator.schedule_sub_every
			ON schedule_sub_every.schedule_sub_every_id = schedule.schedule_sub_every_id
			WHERE true
		) t2
		INNER JOIN pgautomator.dim_date
		ON t2.month_start_date = dim_date.date
	) t
	INNER JOIN pgautomator.dim_date
	ON t.next_run_date = dim_date.date
	WHERE true
	AND t.next_run_date + t.next_run_time >= now()
	AND dim_date.timing = t.timing
	AND dim_date.day_of_week = t.day_of_week
	GROUP BY t.job_id, t.schedule_id
) u
WHERE true
AND job_next_run.job_id = u.job_id
AND job_next_run.schedule_id = u.schedule_id;

/**
* Update the job record with the results
**/
UPDATE pgautomator.job
SET job_next_run = u.job_next_run, job_next_run_schedule_id = u.schedule_id
FROM (
SELECT job_next_run.job_id, job_next_run.schedule_id, job_next_run.next_run as job_next_run
	FROM (
		SELECT job_id, schedule_id, dense_rank() OVER (PARTITION BY job_id ORDER BY next_run asc) as rank
		FROM job_next_run
	) t
	INNER JOIN job_next_run
	ON t.job_id = job_next_run.job_id
	AND t.schedule_id = job_next_run.schedule_id
	WHERE t.rank = 1
) u
WHERE u.job_id = job.job_id;

DROP TABLE IF EXISTS job_next_run;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.set_job_next_run() IS 'Sets the next run information for any jobs which have already run or have not had their next run information set.';


CREATE OR REPLACE FUNCTION pgautomator.create_job_category(_category text)
  RETURNS int AS
$BODY$
DECLARE _job_category_id int;
BEGIN

INSERT INTO pgautomator.job_category(category)
VALUES (_category)
RETURNING job_category_id
INTO _job_category_id;

RETURN _job_category_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.create_job_category(text) IS 'Create a new job category.';

CREATE OR REPLACE FUNCTION pgautomator.remove_job_category(_job_category_id int)
  RETURNS void AS
$BODY$
BEGIN

DELETE
FROM pgautomator.job_category
WHERE job_category_id = _job_category_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.remove_job_category(int) IS 'Remove a job category.';


CREATE OR REPLACE FUNCTION pgautomator.create_job(_job_category_id int, _job_name text, _job_description text, _job_enabled boolean, _job_timeout interval, _job_assigned_agent_id int, _email_on pgautomator.state, _email_to text, _email_subject text, _email_body text)
  RETURNS int AS
$BODY$
DECLARE _job_id int;
BEGIN

INSERT INTO pgautomator.job(job_category_id, job_name, job_description, job_enabled, job_timeout, job_assigned_agent_id, job_created, job_modified)
VALUES (_job_category_id, _job_name, _job_description, _job_enabled, _job_timeout, _job_assigned_agent_id, now(), now())
RETURNING job_id
INTO _job_id;

IF _email_on IS NOT NULL AND _email_to IS NOT NULL AND _email_subject IS NOT NULL AND _email_body IS NOT NULL
THEN
	INSERT INTO pgautomator.job_email (job_id, email_on, email_to, email_subject, email_body)
	VALUES(_job_id, _email_on, _email_to, _email_subject, _email_body);
END IF;

RETURN _job_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.create_job(integer, text, text, boolean, interval, int, pgautomator.state, text, text, text) IS 'Create a new job.';


CREATE OR REPLACE FUNCTION pgautomator.edit_job(_job_id int, _job_category_id int, _job_name text, _job_description text, _job_enabled boolean, _job_timeout interval, _job_assigned_agent_id int, _email_on pgautomator.state, _email_to text, _email_subject text, _email_body text)
  RETURNS void AS
$BODY$
BEGIN

UPDATE pgautomator.job
SET job_category_id=_job_category_id
, job_name=_job_name
, job_description=_job_description
, job_enabled=_job_enabled
, job_timeout=_job_timeout
, job_assigned_agent_id = _job_assigned_agent_id
, job_modified=now()
WHERE job_id = _job_id;

IF _email_on IS NOT NULL AND _email_to IS NOT NULL AND _email_subject IS NOT NULL AND _email_body IS NOT NULL
THEN
	UPDATE pgautomator.job_email
	SET email_on=_email_on
	, email_to=_email_to
	, email_subject=_email_subject
	, email_body=_email_body
	WHERE job_id = _job_id;
ELSE
	DELETE 
	FROM pgautomator.job_email
	WHERE job_id = _job_id;
END IF;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.edit_job(integer, integer, text, text, boolean, interval, int, pgautomator.state, text, text, text) IS 'Edit the properties of an existing job.';

CREATE OR REPLACE FUNCTION pgautomator.remove_job(_job_id int)
  RETURNS void AS
$BODY$
BEGIN

DELETE 
FROM pgautomator.step_log
WHERE step_id IN (
	SELECT step_id
	FROM step
	WHERE job_id = _job_id
);

DELETE 
FROM pgautomator.step_connection
WHERE step_id IN (
	SELECT step_id
	FROM step
	WHERE job_id = _job_id
);

DELETE 
FROM pgautomator.step_email
WHERE step_id IN (
	SELECT step_id
	FROM step
	WHERE job_id = _job_id
);

DELETE 
FROM pgautomator.step
WHERE job_id = _job_id;

DELETE 
FROM pgautomator.job_log
WHERE job_id = _job_id;

DELETE 
FROM pgautomator.job_email
WHERE job_id = _job_id;

DELETE 
FROM pgautomator.job_schedule
WHERE job_id = _job_id;

DELETE 
FROM pgautomator.job
WHERE job_id = _job_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.remove_job(int) IS 'Remove a job and all related information.';




CREATE OR REPLACE FUNCTION pgautomator.create_schedule(
_schedule_name text, _schedule_type pgautomator.schedule_type, _schedule_start_date date, _schedule_end_date date, _schedule_enabled boolean
, _schedule_sub_every_start_at timetz, _schedule_sub_every_end_at timetz, _schedule_sub_every_schedule_interval interval
, _schedule_sub_once_schedule_time timetz, _schedule_type_once_schedule_date date, _schedule_type_daily_schedule_interval int
, _schedule_type_weekly_day_of_week pgautomator.day_of_week, _schedule_type_weekly_schedule_interval int, _schedule_type_monthly_day_of_month int
, _schedule_type_monthly_schedule_interval int, _schedule_type_monthly_relative_timing pgautomator.timing
, _schedule_type_monthly_relative_day_of_week pgautomator.day_of_week, _schedule_type_monthly_relative_schedule_interval int)
  RETURNS int AS
$BODY$
DECLARE 
_schedule_id int;
_schedule_type_once_id int;
_schedule_type_daily_id int;
_schedule_type_weekly_id int;
_schedule_type_monthly_id int;
_schedule_type_monthly_relative_id int;
_schedule_sub_once_id int;
_schedule_sub_every_id int;
BEGIN

SELECT nextval('pgautomator.schedule_schedule_id_seq')
INTO _schedule_id;

IF _schedule_sub_once_schedule_time IS NOT NULL
THEN
	INSERT INTO pgautomator._schedule_sub_once (schedule_id, schedule_time)
	VALUES(_schedule_id, _schedule_sub_once_schedule_time)
	RETURNING schedule_sub_once_id
	INTO _schedule_sub_once_id;
END IF;

IF _schedule_sub_every_start_at IS NOT NULL AND _schedule_sub_every_end_at IS NOT NULL AND _schedule_sub_every_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_sub_every (schedule_id, start_at, end_at, schedule_interval)
	VALUES(_schedule_id, _schedule_sub_every_start_at, _schedule_sub_every_end_at, _schedule_sub_every_schedule_interval)
	RETURNING schedule_sub_every_id
	INTO _schedule_sub_every_id;
END IF;

IF _schedule_type_once_schedule_date IS NOT NULL
THEN
	INSERT INTO pgautomator._schedule_sub_once (schedule_id, schedule_date)
	VALUES(_schedule_id, _schedule_type_once_schedule_date)
	RETURNING schedule_type_once_id
	INTO _schedule_type_once_id;
END IF;

IF _schedule_type_daily_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_daily (schedule_id, schedule_interval)
	VALUES(_schedule_id, _schedule_type_daily_schedule_interval)
	RETURNING schedule_type_daily_id
	INTO _schedule_type_daily_id;
END IF;

IF _schedule_type_weekly_day_of_week IS NOT NULL AND _schedule_type_weekly_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_weekly (schedule_id, day_of_week, schedule_interval)
	VALUES(_schedule_id, _schedule_type_weekly_day_of_week, _schedule_type_weekly_schedule_interval)
	RETURNING schedule_type_weekly_id
	INTO _schedule_type_weekly_id;
END IF;

IF _schedule_type_monthly_day_of_month IS NOT NULL AND _schedule_type_monthly_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_monthly (schedule_id, day_of_month, schedule_interval)
	VALUES(_schedule_id, _schedule_type_monthly_day_of_month, _schedule_type_monthly_schedule_interval)
	RETURNING schedule_type_monthly_id
	INTO _schedule_type_monthly_id;
END IF;

IF _schedule_type_monthly_relative_timing IS NOT NULL AND _schedule_type_monthly_relative_day_of_week IS NOT NULL AND _schedule_type_monthly_relative_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_monthly_relative (schedule_id, timing, day_of_week, schedule_interval)
	VALUES(_schedule_id, _schedule_type_monthly_relative_timing, _schedule_type_monthly_relative_day_of_week, _schedule_type_monthly_relative_schedule_interval)
	RETURNING schedule_type_monthly_relative_id
	INTO _schedule_type_monthly_relative_id;
END IF;

INSERT INTO pgautomator.schedule(schedule_id, schedule_name, schedule_type, schedule_start_date, schedule_end_date, schedule_enabled
, schedule_type_once_id, schedule_type_daily_id, schedule_type_weekly_id, schedule_type_monthly_id
, schedule_type_monthly_relative_id, schedule_sub_once_id, schedule_sub_every_id)
VALUES (_schedule_id, _schedule_name, _schedule_type, _schedule_start_date, _schedule_end_date, _schedule_enabled
, _schedule_type_once_id, _schedule_type_daily_id, _schedule_type_weekly_id, _schedule_type_monthly_id
, _schedule_type_monthly_relative_id, _schedule_sub_once_id, _schedule_sub_every_id)
RETURNING schedule_id
INTO _schedule_id;

RETURN _schedule_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.create_schedule(text, pgautomator.schedule_type, date, date, boolean, time with time zone, time with time zone, interval, time with time zone, date, integer, pgautomator.day_of_week, integer, integer, integer, pgautomator.timing, pgautomator.day_of_week, integer) IS 'Create a new schedule.';


CREATE OR REPLACE FUNCTION pgautomator.edit_schedule(
_schedule_id int, _schedule_name text, _schedule_type pgautomator.schedule_type, _schedule_start_date date, _schedule_end_date date, _schedule_enabled boolean
, _schedule_sub_every_start_at timetz, _schedule_sub_every_end_at timetz, _schedule_sub_every_schedule_interval interval
, _schedule_sub_once_schedule_time timetz, _schedule_type_once_schedule_date date, _schedule_type_daily_schedule_interval int
, _schedule_type_weekly_day_of_week pgautomator.day_of_week, _schedule_type_weekly_schedule_interval int, _schedule_type_monthly_day_of_month int
, _schedule_type_monthly_schedule_interval int, _schedule_type_monthly_relative_timing pgautomator.timing
, _schedule_type_monthly_relative_day_of_week pgautomator.day_of_week, _schedule_type_monthly_relative_schedule_interval int)
  RETURNS void AS
$BODY$
DECLARE 
_schedule_type_once_id int;
_schedule_type_daily_id int;
_schedule_type_weekly_id int;
_schedule_type_monthly_id int;
_schedule_type_monthly_relative_id int;
_schedule_sub_once_id int;
_schedule_sub_every_id int;
BEGIN

UPDATE pgautomator.schedule
SET schedule_name=_schedule_name
, schedule_type=_schedule_type
, schedule_start_date=_schedule_start_date
, schedule_end_date=_schedule_end_date
, schedule_enabled=_schedule_enabled
WHERE schedule_id = _schedule_id;

DELETE FROM pgautomator.schedule_sub_every WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_sub_once WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_once WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_daily WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_weekly WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_monthly WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_monthly_relative WHERE schedule_id = _schedule_id;

IF _schedule_sub_once_schedule_time IS NOT NULL
THEN
	INSERT INTO pgautomator._schedule_sub_once (schedule_id, schedule_time)
	VALUES(_schedule_id, _schedule_sub_once_schedule_time)
	RETURNING schedule_sub_once_id
	INTO _schedule_sub_once_id;
END IF;

IF _schedule_sub_every_start_at IS NOT NULL AND _schedule_sub_every_end_at IS NOT NULL AND _schedule_sub_every_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_sub_every (schedule_id, start_at, end_at, schedule_interval)
	VALUES(_schedule_id, _schedule_sub_every_start_at, _schedule_sub_every_end_at, _schedule_sub_every_schedule_interval)
	RETURNING schedule_sub_every_id
	INTO _schedule_sub_every_id;
END IF;

IF _schedule_type_once_schedule_date IS NOT NULL
THEN
	INSERT INTO pgautomator._schedule_sub_once (schedule_id, schedule_date)
	VALUES(_schedule_id, _schedule_type_once_schedule_date)
	RETURNING schedule_type_once_id
	INTO _schedule_type_once_id;
END IF;

IF _schedule_type_daily_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_daily (schedule_id, schedule_interval)
	VALUES(_schedule_id, _schedule_type_daily_schedule_interval)
	RETURNING schedule_type_daily_id
	INTO _schedule_type_daily_id;
END IF;

IF _schedule_type_weekly_day_of_week IS NOT NULL AND _schedule_type_weekly_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_weekly (schedule_id, day_of_week, schedule_interval)
	VALUES(_schedule_id, _schedule_type_weekly_day_of_week, _schedule_type_weekly_schedule_interval)
	RETURNING schedule_type_weekly_id
	INTO _schedule_type_weekly_id;
END IF;

IF _schedule_type_monthly_day_of_month IS NOT NULL AND _schedule_type_monthly_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_monthly (schedule_id, day_of_month, schedule_interval)
	VALUES(_schedule_id, _schedule_type_monthly_day_of_month, _schedule_type_monthly_schedule_interval)
	RETURNING schedule_type_monthly_id
	INTO _schedule_type_monthly_id;
END IF;

IF _schedule_type_monthly_relative_timing IS NOT NULL AND _schedule_type_monthly_relative_day_of_week IS NOT NULL AND _schedule_type_monthly_relative_schedule_interval IS NOT NULL
THEN
	INSERT INTO pgautomator.schedule_type_monthly_relative (schedule_id, timing, day_of_week, schedule_interval)
	VALUES(_schedule_id, _schedule_type_monthly_relative_timing, _schedule_type_monthly_relative_day_of_week, _schedule_type_monthly_relative_schedule_interval)
	RETURNING schedule_type_monthly_relative_id
	INTO _schedule_type_monthly_relative_id;
END IF;

UPDATE pgautomator.schedule
SET schedule_type_once_id=_schedule_type_once_id
, schedule_type_daily_id=_schedule_type_daily_id
, schedule_type_weekly_id=_schedule_type_weekly_id
, schedule_type_monthly_id=_schedule_type_monthly_id
, schedule_type_monthly_relative_id=_schedule_type_monthly_relative_id
, schedule_sub_once_id=_schedule_sub_once_id
, schedule_sub_every_id=_schedule_sub_every_id
WHERE schedule_id = _schedule_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.edit_schedule(integer, text, pgautomator.schedule_type, date, date, boolean, time with time zone, time with time zone, interval, time with time zone, date, integer, pgautomator.day_of_week, integer, integer, integer, pgautomator.timing, pgautomator.day_of_week, integer) IS 'Edit the properties for a schedule.';



CREATE OR REPLACE FUNCTION pgautomator.assign_schedule(_job_id int, _schedule_id int)
  RETURNS void AS
$BODY$

INSERT INTO pgautomator.job_schedule(job_id, schedule_id)
VALUES(_job_id, _schedule_id);

UPDATE pgautomator.job
SET job_next_run_schedule_id = null, job_next_run = null
WHERE true
AND job.job_id = _job_id
AND job.job_executing_agent_id IS NULL;

SELECT pgautomator.set_job_next_run();

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.assign_schedule(integer, integer) IS 'Add the schedule to a specific job.';


CREATE OR REPLACE FUNCTION pgautomator.unassign_schedule(_job_id int, _schedule_id int)
  RETURNS void AS
$BODY$

DELETE 
FROM pgautomator.job_schedule 
WHERE true
AND schedule_id = _schedule_id
AND job_id = _job_id;

UPDATE pgautomator.job
SET job_next_run_schedule_id = null, job_next_run = null
WHERE true
AND job.job_id = _job_id
AND job.job_executing_agent_id IS NULL;

SELECT pgautomator.set_job_next_run();

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.unassign_schedule(integer, integer) IS 'Remove the schedule from a specific job.';

CREATE OR REPLACE FUNCTION pgautomator.remove_schedule(_schedule_id int)
  RETURNS void AS
$BODY$

DELETE FROM pgautomator.job_schedule WHERE schedule_id = _schedule_id;

DELETE FROM pgautomator.schedule_sub_every WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_sub_once WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_once WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_daily WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_weekly WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_monthly WHERE schedule_id = _schedule_id;
DELETE FROM pgautomator.schedule_type_monthly_relative WHERE schedule_id = _schedule_id;

DELETE FROM pgautomator.schedule WHERE schedule_id = _schedule_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.remove_schedule(integer) IS 'Remove the schedule from the system.';



CREATE OR REPLACE FUNCTION pgautomator.create_step(
_job_id int, _step_name text, _step_description text, _step_index int, _step_enabled boolean, 
_step_type pgautomator.step_type, _step_database_name text, _step_timeout interval, _step_success_code int,
_step_retry_attempts int, _step_retry_interval interval, _step_on_fail_action pgautomator.step_action, 
_step_on_fail_step_id int, _step_on_success_action pgautomator.step_action, _step_on_success_step_id int,
_step_command text, _step_database_host text, _step_database_login text, _step_database_pass text,
_step_database_auth_query text, _email_on pgautomator.state, _email_to text, _email_subject text, _email_body text)
  RETURNS int AS
$BODY$
DECLARE _step_id int;
BEGIN

INSERT INTO pgautomator.step(job_id, step_name, step_description, step_index, step_enabled, 
			step_type, step_database_name, step_timeout, step_success_code,
			step_retry_attempts, step_retry_interval, step_on_fail_action,
			step_on_fail_step_id, step_on_success_action, step_on_success_step_id, 
			step_command)
VALUES (_job_id, _step_name, _step_description, _step_index, _step_enabled, 
			_step_type, _step_database_name, _step_timeout, _step_success_code, 
			_step_retry_attempts, _step_retry_interval, _step_on_fail_action,
			_step_on_fail_step_id, _step_on_success_action, _step_on_success_step_id, 
			_step_command)
RETURNING step_id
INTO _step_id;


IF _step_database_host IS NOT NULL AND _step_database_login IS NOT NULL
THEN
	INSERT INTO pgautomator.step_connection (step_id, step_database_host, step_database_login, step_database_pass, step_database_auth_query)
	VALUES(_step_id, _step_database_host, _step_database_login, _step_database_pass, _step_database_auth_query);
END IF;

IF _email_on IS NOT NULL AND _email_to IS NOT NULL AND _email_subject IS NOT NULL AND _email_body IS NOT NULL
THEN
	INSERT INTO pgautomator.step_email (step_id, email_on, email_to, email_subject, email_body)
	VALUES(_step_id, _email_on, _email_to, _email_subject, _email_body);
END IF;

RETURN _step_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.create_step(integer, text, text, integer, boolean, pgautomator.step_type, text, interval, integer, integer, interval, pgautomator.step_action, integer, pgautomator.step_action, integer, text, text, text, text, text, pgautomator.state, text, text, text) IS 'Creates a new step for a job.';


CREATE OR REPLACE FUNCTION pgautomator.edit_step(
_step_id int, _step_name text, _step_description text, _step_index int, _step_enabled boolean, 
_step_type pgautomator.step_type, _step_database_name text, _step_timeout interval, _step_success_code int,
_step_retry_attempts int, _step_retry_interval interval, _step_on_fail_action pgautomator.step_action, 
_step_on_fail_step_id int, _step_on_success_action pgautomator.step_action, _step_on_success_step_id int,
_step_command text, _step_database_host text, _step_database_login text, _step_database_pass text,
_step_database_auth_query text, _email_on pgautomator.state, _email_to text, _email_subject text, _email_body text)
  RETURNS void AS
$BODY$
BEGIN

UPDATE pgautomator.step
SET step_name=_step_name
, step_description=_step_description
, step_index=_step_index
, step_enabled=_step_enabled
, step_type=_step_type
, step_database_name=_step_database_name
, step_timeout=_step_timeout
, step_success_code=_step_success_code
, step_retry_attempts=_step_retry_attempts
, step_retry_interval=_step_retry_interval
, step_on_fail_action=_step_on_fail_action
, step_on_fail_step_id=_step_on_fail_step_id
, step_on_success_action=_step_on_success_action
, step_on_success_step_id=_step_on_success_step_id
, step_command=_step_command
WHERE step_id = _step_id;

IF _step_database_host IS NOT NULL AND _step_database_login IS NOT NULL
THEN
	UPDATE pgautomator.step_email
	SET step_database_host=_step_database_host
	, step_database_login=_step_database_login
	, step_database_pass=_step_database_pass
	, step_database_auth_query=_step_database_auth_query
	WHERE step_id = _step_id;
ELSE
	DELETE 
	FROM pgautomator.step_email
	WHERE step_id = _step_id;
END IF;

IF _email_on IS NOT NULL AND _email_to IS NOT NULL AND _email_subject IS NOT NULL AND _email_body IS NOT NULL
THEN
	UPDATE pgautomator.step_email
	SET email_on=_email_on
	, email_to=_email_to
	, email_subject=_email_subject
	, email_body=_email_body
	WHERE step_id = _step_id;
ELSE
	DELETE 
	FROM pgautomator.step_email
	WHERE step_id = _step_id;
END IF;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.edit_step(integer, text, text, integer, boolean, pgautomator.step_type, text, interval, integer, integer, interval, pgautomator.step_action, integer, pgautomator.step_action, integer, text, text, text, text, text, pgautomator.state, text, text, text) IS 'Edit the step properties.';

CREATE OR REPLACE FUNCTION pgautomator.get_steps(_job_id int)
  RETURNS TABLE (step_id int, step_name text, step_type pgautomator.step_type, step_database_name text, step_timeout_ms bigint, step_success_code int, step_retry_attempts int, step_retry_interval_ms bigint, step_on_fail_action pgautomator.step_action, step_on_fail_step_id int, step_on_success_action pgautomator.step_action, step_on_success_step_id int, step_command text, step_database_host text, step_database_login text, step_database_pass text, step_database_auth_query text, email_on pgautomator.state, email_to text[], email_subject text, email_body text) AS
$BODY$

SELECT step.step_id
, step.step_name
, step.step_type
, step.step_database_name
, (EXTRACT(EPOCH FROM step.step_timeout) * 1000)::bigint AS step_timeout_ms
, step.step_success_code
, step.step_retry_attempts
, (EXTRACT(EPOCH FROM step.step_retry_interval) * 1000)::bigint AS step_retry_interval_ms
, step.step_on_fail_action
, step.step_on_fail_step_id
, step.step_on_success_action
, step.step_on_success_step_id
, step.step_command
, step_connection.step_database_host
, step_connection.step_database_login
, step_connection.step_database_pass
, step_connection.step_database_auth_query
, step_email.email_on
, step_email.email_to
, step_email.email_subject
, step_email.email_body
FROM pgautomator.step
LEFT JOIN pgautomator.step_connection
ON step.step_id = step_connection.step_id
LEFT JOIN pgautomator.step_email
ON step.step_id = step_email.step_id
WHERE true
AND step.step_enabled = true
AND step.job_id = _job_id
ORDER BY step.step_index;

$BODY$
LANGUAGE sql STABLE;
COMMENT ON FUNCTION pgautomator.get_steps(integer) IS 'Returns the steps for a job and all required info to process.';

CREATE OR REPLACE FUNCTION pgautomator.remove_step(_step_id int)
  RETURNS void AS
$BODY$
BEGIN

DELETE 
FROM pgautomator.step_log
WHERE step_id = _step_id;

DELETE 
FROM pgautomator.step_connection
WHERE step_id = _step_id;

DELETE 
FROM pgautomator.step_email
WHERE step_id = _step_id;

DELETE 
FROM pgautomator.step
WHERE step_id = _step_id;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.remove_step(integer) IS 'Remove the step from the system.';


CREATE OR REPLACE FUNCTION pgautomator.edit_agent(_agent_id int, _agent_description text, _agent_poll_interval interval, _smtp_email text, _smtp_host text, _smtp_port int, _smtp_ssl boolean, _smtp_user text, _smtp_password text)
  RETURNS void AS
$BODY$
BEGIN

UPDATE pgautomator.agent
SET agent_description=_agent_description
, agent_poll_interval=_agent_poll_interval
WHERE agent_id = _agent_id;

IF _smtp_email IS NOT NULL AND _smtp_host IS NOT NULL AND _smtp_port IS NOT NULL AND _smtp_ssl IS NOT NULL
THEN
	INSERT INTO pgautomator.agent_smtp (agent_id, smtp_email, smtp_host, smtp_port, smtp_ssl, smtp_user, smtp_password)
	VALUES (_agent_id, _smtp_email, _smtp_host, _smtp_port, _smtp_ssl, _smtp_user, _smtp_password)
	ON CONFLICT ON CONSTRAINT agent_smtp_agent_id_key DO UPDATE SET 
	smtp_email=_smtp_email
	, smtp_host=_smtp_host
	, smtp_port=_smtp_port
	, smtp_ssl=_smtp_ssl
	, smtp_user=_smtp_user
	, smtp_password=_smtp_password;
ELSE
	DELETE 
	FROM pgautomator.agent_smtp
	WHERE agent_id = _agent_id;
END IF;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.edit_agent(integer, text, interval, text, text, integer, boolean, text, text) IS 'Edit agent properties.';


CREATE OR REPLACE FUNCTION pgautomator.remove_agent(_agent_id int)
  RETURNS void AS
$BODY$

DELETE 
FROM pgautomator.agent_smtp
WHERE agent_id = _agent_id;

DELETE
FROM pgautomator.agent
WHERE agent_id = _agent_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.remove_agent(int) IS 'Remove agent from the system.  Only possible if agent has not executed any jobs.';


CREATE OR REPLACE FUNCTION pgautomator.get_random_agent()
  RETURNS int AS
$BODY$

SELECT agent_id
FROM pgautomator.agent_active
ORDER BY random()
LIMIT 1;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.get_random_agent() IS 'Returns the id of a random active agent.';


CREATE OR REPLACE FUNCTION pgautomator.get_jobs(_agent_id int)
  RETURNS TABLE (job_id int, job_name text, job_timeout_ms bigint, email_on pgautomator.state, email_to text[], email_subject text, email_body text)AS
$BODY$
BEGIN

/**
* Update agent to let it know that it's still active.
**/
UPDATE pgautomator.agent
SET agent_last_poll = now()
WHERE agent_id = _agent_id;

/**
* Get all eligible jobs
**/
RETURN QUERY WITH jobs_to_update AS (
UPDATE pgautomator.job
SET job_executing_agent_id = _agent_id
WHERE true
AND job.job_enabled = true
AND (job.job_assigned_agent_id = _agent_id OR (job.job_assigned_agent_id IS NULL AND pgautomator.get_random_agent() = _agent_id))
AND job.job_executing_agent_id IS NULL
AND job.job_next_run <= now()
RETURNING job.job_id
)
SELECT job.job_id
, job.job_name 
, (EXTRACT(EPOCH FROM job.job_timeout) * 1000)::bigint AS job_timeout_ms
, job_email.email_on 
, job_email.email_to 
, job_email.email_subject 
, job_email.email_body 
FROM pgautomator.job
LEFT JOIN pgautomator.job_email
ON job.job_id = job_email.job_id
WHERE job.job_id IN (
	SELECT jobs_to_update.job_id
	FROM jobs_to_update
);

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.get_jobs(int) IS 'Returns the ids jobs this agent should run at this point. If there are multiple active agents and the job is not assigned to a perticular one, this will assign it to a random agent.';


CREATE OR REPLACE FUNCTION pgautomator.clear_job_executing_agent(_job_id int)
  RETURNS void AS
$BODY$

/**
* Update job to no longer have an executing agent
**/
UPDATE pgautomator.job
SET job_executing_agent_id = null, job_next_run_schedule_id = null, job_next_run = null
WHERE job_id = _job_id;

/**
* Schedule the next run
**/
SELECT pgautomator.set_job_next_run();

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.clear_job_executing_agent(int) IS 'Clears the flags on the job after execution is complete.';


CREATE OR REPLACE FUNCTION pgautomator.begin_job_log(_job_id int)
  RETURNS int AS
$BODY$

/**
* Insert logging info
**/
INSERT INTO pgautomator.job_log(job_id, agent_id, schedule_id, job_log_state, job_log_start)
SELECT job.job_id, job.job_executing_agent_id, job.job_next_run_schedule_id, 'RUNNING', now()
FROM pgautomator.job
WHERE job.job_id = _job_id
RETURNING job_log_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.begin_job_log(int) IS 'Logging function for job';


CREATE OR REPLACE FUNCTION pgautomator.finish_job_log(_job_log_id int, _job_log_state pgautomator.state)
  RETURNS void AS
$BODY$

/**
* Update logging info
**/
UPDATE pgautomator.job_log
SET job_log_state = _job_log_state
, job_log_duration = now() - job_log_start
WHERE job_log_id = _job_log_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.finish_job_log(int, pgautomator.state) IS 'Logging function for job';



CREATE OR REPLACE FUNCTION pgautomator.begin_step_log(_job_log_id int, _step_id int)
  RETURNS int AS
$BODY$

/**
* Insert logging info
**/
INSERT INTO pgautomator.step_log(job_log_id, step_id, step_log_state, step_log_start)
VALUES (_job_log_id, _step_id, 'RUNNING', now())
RETURNING step_log_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.begin_step_log(int, int) IS 'Logging function for step';


CREATE OR REPLACE FUNCTION pgautomator.finish_step_log(_step_log_id int, _step_log_state pgautomator.state, _step_log_exit_code int, _step_log_retries int, _step_log_message text)
  RETURNS void AS
$BODY$

/**
* Update logging info
**/
UPDATE pgautomator.step_log
SET step_log_state = _step_log_state
, step_log_duration = now() - step_log_start
, step_log_exit_code = _step_log_exit_code
, step_log_retries = _step_log_retries
, step_log_message = _step_log_message
WHERE step_log_id = _step_log_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.finish_step_log(int, pgautomator.state, int, int, text) IS 'Logging function for step';



CREATE OR REPLACE FUNCTION pgautomator.kill_job(_job_id int)
  RETURNS void AS
$BODY$

INSERT INTO pgautomator.job_kill (job_id)
VALUES (_job_id)
ON CONFLICT (job_id) DO NOTHING;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.kill_job(int) IS 'Marks the job to be killed by the agent running it';

CREATE OR REPLACE FUNCTION pgautomator.get_killed_jobs(_agent_id int)
  RETURNS SETOF int AS
$BODY$

DELETE 
FROM pgautomator.job_kill
WHERE EXISTS (
	SELECT 1
	FROM pgautomator.job
	WHERE true
	AND job_kill.job_id = job.job_id
	AND job.job_executing_agent_id = _agent_id
)
RETURNING job_kill.job_id;

$BODY$
LANGUAGE sql VOLATILE;
COMMENT ON FUNCTION pgautomator.kill_job(int) IS 'Gets jobs running on the agent which need to be killed and removes them from the table to be killed.';

CREATE OR REPLACE FUNCTION pgautomator.zombie_killer(_agent_id int)
  RETURNS void AS
$BODY$
BEGIN

CREATE TEMP TABLE IF NOT EXISTS tmp_zombies(agent_id int);

INSERT INTO tmp_zombies (agent_id)
SELECT _agent_id;

PERFORM pgautomator.zombie_killer();

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.zombie_killer(int) IS 'Cleanup function for if an agent disconnects while a job is running';

CREATE OR REPLACE FUNCTION pgautomator.zombie_killer()
  RETURNS void AS
$BODY$
BEGIN

CREATE TEMP TABLE IF NOT EXISTS tmp_zombies(agent_id int);

INSERT INTO tmp_zombies (agent_id)
SELECT agent_id
FROM pgautomator.agent
WHERE NOT EXISTS (
SELECT 1
FROM pgautomator.agent_active
WHERE agent_active.agent_id = agent.agent_id);

IF (SELECT count(1) FROM tmp_zombies) = 0
THEN
	DROP TABLE IF EXISTS tmp_zombies;
	RETURN;
END IF;

UPDATE pgautomator.job_log 
SET job_log_state = 'ABORTED'
WHERE job_log_id IN (
	SELECT job_log.job_log_id
	FROM tmp_zombies
	INNER JOIN pgautomator.job
	ON tmp_zombies.agent_id = job.job_executing_agent_id
	INNER JOIN pgautomator.job_log
	ON job.job_id = job_log.job_id
	WHERE job_log.job_log_state = 'RUNNING'
);

UPDATE pgautomator.step_log 
SET step_log_state = 'ABORTED'
WHERE step_log_id IN (
	SELECT step_log.step_log_id
	FROM tmp_zombies
	INNER JOIN pgautomator.job
	ON tmp_zombies.agent_id = job.job_executing_agent_id
	INNER JOIN pgautomator.job_log
	ON job.job_id = job_log.job_id
	INNER JOIN pgautomator.step_log
	ON job_log.job_log_id = step_log.job_log_id
	WHERE step_log.step_log_state = 'RUNNING'
);

UPDATE pgautomator.step_log 
SET step_log_state = 'ABORTED'
WHERE step_log_id IN (
	SELECT step_log.step_log_id
	FROM pgautomator.job_log
	INNER JOIN pgautomator.step_log
	ON job_log.job_log_id = step_log.job_log_id
	WHERE TRUE
	AND job_log.job_log_state <> 'RUNNING'
	AND step_log.step_log_state = 'RUNNING'
);

UPDATE pgautomator.job 
SET job_next_run_schedule_id = null
, job_next_run = null
, job_executing_agent_id = null
WHERE job_executing_agent_id IN (
	SELECT agent_id 
	FROM tmp_zombies
);

PERFORM pgautomator.set_job_next_run();

DROP TABLE tmp_zombies;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.zombie_killer() IS 'Cleanup function for if an agent disconnects while a job is running';



CREATE OR REPLACE FUNCTION pgautomator.register_agent(_agent_identifier text)
  RETURNS TABLE (agent_id int, agent_poll_interval_ms bigint, smtp_email text, smtp_host text, smtp_port integer, smtp_ssl boolean, smtp_user text, smtp_password text) AS
$BODY$
BEGIN

PERFORM pgautomator.zombie_killer(agent.agent_id)
FROM pgautomator.agent
WHERE true
AND agent.agent_identifier = _agent_identifier
AND agent.agent_pid != pg_backend_pid();

INSERT INTO pgautomator.agent(agent_identifier, agent_poll_interval, agent_registered, agent_pid)
SELECT _agent_identifier, '10 seconds'::interval, now(), pg_backend_pid()
WHERE NOT EXISTS (
	SELECT 1
	FROM pgautomator.agent
	WHERE agent.agent_identifier = _agent_identifier);

UPDATE pgautomator.agent 
SET agent_pid = pg_backend_pid()
WHERE true
AND agent.agent_identifier = _agent_identifier
AND agent.agent_pid != pg_backend_pid();

RETURN QUERY SELECT 
	agent.agent_id
	, (EXTRACT(EPOCH FROM agent.agent_poll_interval) * 1000)::bigint AS agent_poll_interval_ms
	, agent_smtp.smtp_email
	, agent_smtp.smtp_host
	, agent_smtp.smtp_port
	, agent_smtp.smtp_ssl
	, agent_smtp.smtp_user
	, agent_smtp.smtp_password
	FROM pgautomator.agent
	LEFT JOIN pgautomator.agent_smtp
	USING (agent_id)
	WHERE agent.agent_identifier = _agent_identifier;

END;
$BODY$
LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION pgautomator.register_agent(text) IS 'Create a new agent. Called by the agent itself when started.';


/**
* Test stuff, need to finish testing everything
**/

/*

SELECT pgautomator.create_job(
    _job_category_id := 1,
    _job_name := 'test',
    _job_description := 'This is a test job',
    _job_enabled := true,
    _job_timeout := null,
    _job_assigned_agent_id := null,
    _email_on := null,
    _email_to := null,
    _email_subject := null,
    _email_body := null
);

SELECT pgautomator.create_step(
    _job_id  := 1,
    _step_name := 'test step 1',
    _step_description := null,
    _step_index := 1,
    _step_enabled := true,
    _step_type := 'SQL'::pgautomator.step_type,
    _step_database_name := 'manufacturer',
    _step_timeout := null,
    _step_success_code := null,
    _step_retry_attempts := 0,
    _step_retry_interval := '0 seconds',
    _step_on_fail_action := 'QUIT_FAILED',
    _step_on_fail_step_id := null,
    _step_on_success_action := 'STEP_NEXT',
    _step_on_success_step_id := null,
    _step_command := 'SELECT 1',
    _step_database_host := null,
    _step_database_login := null,
    _step_database_pass := null,
    _step_database_auth_query := null,
    _email_on := null,
    _email_to := null,
    _email_subject := null,
    _email_body := null
);


SELECT pgautomator.create_schedule(
    _schedule_name := 'test schedule',
    _schedule_type := 'DATE',
    _schedule_start_date := now()::date,
    _schedule_end_date := null,
    _schedule_enabled := true,
    _schedule_sub_every_start_at := '00:00:00+00',
    _schedule_sub_every_end_at := '24:00:00+00',
    _schedule_sub_every_schedule_interval := '3 min',
    _schedule_sub_once_schedule_time := null,
    _schedule_type_once_schedule_date := null,
    _schedule_type_daily_schedule_interval := 1,
    _schedule_type_weekly_day_of_week := null,
    _schedule_type_weekly_schedule_interval := null,
    _schedule_type_monthly_day_of_month := null,
    _schedule_type_monthly_schedule_interval := null,
    _schedule_type_monthly_relative_timing := null,
    _schedule_type_monthly_relative_day_of_week := null,
    _schedule_type_monthly_relative_schedule_interval := null
);

SELECT pgautomator.create_schedule(
    _schedule_name := 'test schedule 2',
    _schedule_type := 'DATE',
    _schedule_start_date := now()::date,
    _schedule_end_date := null,
    _schedule_enabled := true,
    _schedule_sub_every_start_at := '00:00:00+00',
    _schedule_sub_every_end_at := '24:00:00+00',
    _schedule_sub_every_schedule_interval := '45 seconds',
    _schedule_sub_once_schedule_time := null,
    _schedule_type_once_schedule_date := null,
    _schedule_type_daily_schedule_interval := 1,
    _schedule_type_weekly_day_of_week := null,
    _schedule_type_weekly_schedule_interval := null,
    _schedule_type_monthly_day_of_month := null,
    _schedule_type_monthly_schedule_interval := null,
    _schedule_type_monthly_relative_timing := null,
    _schedule_type_monthly_relative_day_of_week := null,
    _schedule_type_monthly_relative_schedule_interval := null
);

SELECT pgautomator.assign_schedule(_job_id := 1, _schedule_id := 1);
SELECT pgautomator.assign_schedule(_job_id := 1, _schedule_id := 2);

SELECT pgautomator.set_job_next_run();

SELECT * FROM pgautomator.register_agent('test4');

SELECT *
FROM pgautomator.job;

UPDATE pgautomator.job
SET job_executing_agent_id = null
, job_next_run = null


SELECT agent_id
FROM pgautomator.agent
WHERE NOT EXISTS (
SELECT 1
FROM pgautomator.agent_active
WHERE agent_active.agent_id = agent.agent_id);

SELECT *
FROM pgautomator.job_log;

SELECT *
FROM pgautomator.step;

SELECT *
FROM pgautomator.step_log;

SELECT *
FROM pgautomator.schedule;

SELECT *
FROM pgautomator.job_schedule;

*/

COMMIT TRANSACTION;