-- ---------------------------------------------------------------
-- Daily jobs (Supabase only; run after refresh_sample_dates.sql).
--
-- pg_cron runs SQL on a timetable inside the database, so nothing else
-- has to be running. Times are UTC: 09:00 UTC is 3 AM in Arkansas
-- (4 AM during daylight saving time).
--
--   See the jobs:       select jobname, schedule, command from cron.job;
--   See recent runs:    select * from cron.job_run_details order by start_time desc limit 5;
--   Stop the refresh:   select cron.unschedule('stagecall-refresh-sample-dates');
-- ---------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

-- Keep the demo's sample gigs on the coming Fri / Sat / Sun, every day.
-- cron.schedule with the same name replaces the job, so this is safe to rerun.
select cron.schedule('stagecall-refresh-sample-dates', '0 9 * * *', 'select private.refresh_sample_dates()');
