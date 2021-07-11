use msdb
set ansi_nulls on
set quoted_identifier on
go

if exists (	select	1
			from	INFORMATION_SCHEMA.VIEWS
			where TABLE_NAME = 'vw_job_run_status' and TABLE_SCHEMA ='dbo')
begin
	drop view dbo.vw_job_run_status
end
go

/*
A long time ago, created by github.com/corelevel
*/
create view dbo.vw_job_run_status
as
select distinct jo.[name],
		dbo.agent_datetime(joh.run_date,joh.run_time) last_run_date,
		case	when exists
					(
					select	1
					from	dbo.sysjobactivity joa_
					where joa_.job_id = jo.job_id
						and joa_.start_execution_date >= joh.run_time
						and joa_.start_execution_date is not null
						and joa_.stop_execution_date is null
					) then 'Executing'
				when joh.run_status = 0 then 'Failed'
				when joh.run_status = 1 then 'Success'
				when joh.run_status = 2 then 'Retry'
				when joh.run_status = 3 then 'Canceled'
		end run_status
from	dbo.sysjobs jo
		join dbo.sysjobhistory joh
		on joh.job_id = jo.job_id
where joh.run_date = (select max(joh_.run_date) from dbo.sysjobhistory joh_ where joh_.job_id = jo.job_id)
	and joh.run_time = (select max(joh_.run_time) from dbo.sysjobhistory joh_ where joh_.job_id = jo.job_id and joh_.run_date = joh.run_date)
go