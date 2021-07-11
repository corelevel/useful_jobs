use msdb
set ansi_nulls on
set quoted_identifier on
go

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Monitoring_CheckMirroring' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Monitoring_CheckMirroring
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Monitoring_CheckMirroring
	@recreate bit = 0
as

set nocount on

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Monitoring_CheckMirroring'
set @schedule_name = 'Schedule' + @job_name
set @description = 'Mirroring monitoring'
set @operator = 'dba_notify'

if @recreate = 1
begin
	if exists(select 1 from dbo.sysjobs where [name] = @job_name)
	begin
		exec msdb.dbo.sp_delete_job @job_name=@job_name
	end

	exec dbo.sp_add_job @job_name=@job_name,@enabled=1,@notify_level_eventlog=0,@notify_level_email=0,@notify_level_netsend=0,@notify_level_page=2,@delete_level=0,@description=@description,@owner_login_name=N'sa',@notify_page_operator_name=@operator,@job_id=@job_id output
	exec dbo.sp_add_jobserver @job_name = @job_name, @server_name = @@servername
end
else
begin
	select @job_id = job_id from dbo.sysjobs where [name] = @job_name
	
	if @job_id is null
	begin
		raiserror ('Job doesn''t exist', 16, 1)
		return
	end

	exec dbo.sp_delete_jobstep @job_name = @job_name, @step_id = 0
end

exec dbo.sp_add_jobstep @job_id=@job_id, @step_name=N'Sync state check', 
	@step_id=1, 
	@cmdexec_success_code=0, 
	@on_success_action=3, 
	@on_fail_action=3, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'if exists(select 1 from sys.database_mirroring where mirroring_state_desc is not null and mirroring_state_desc <> ''SYNCHRONIZED'')
begin
	raiserror (''Mirroring synchronization state is not healthy'', 16, 1)
end',
	@database_name=N'master', 
	@flags=0

exec dbo.sp_add_jobstep @job_id=@job_id, @step_name=N'Unsent log size check', 
	@step_id=2, 
	@cmdexec_success_code=0, 
	@on_success_action=1, 
	@on_fail_action=2, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'set nocount on

declare @threshold int	-- in KB

set @threshold = 1024 * 100 -- 100 MB

create table #dbmmonitorresults
(
database_name		sysname,
[role]				int,
mirroring_state		int,
witness_status		int,
log_generation_rate	int,
unsent_log			int,
send_rate			int,
unrestored_log		int,
recovery_rate		int,
transaction_delay	int,
transactions_per_sec	int,
average_delay		int,
time_recorded		datetime,
time_behind			datetime,
local_time			datetime
)

declare @database_name sysname

declare database_cursor cursor fast_forward for
select	db_name(database_id) [database_name]
from	sys.database_mirroring
where mirroring_role is not null
order by [database_name]

open database_cursor
 
while 1 = 1
begin
	fetch next from database_cursor into @database_name
	if @@fetch_status <> 0 break

	insert	#dbmmonitorresults
	exec sys.sp_dbmmonitorresults @database_name, 0, 0
end

close database_cursor
deallocate database_cursor

if exists(select 1 from #dbmmonitorresults where unrestored_log > @threshold or unsent_log > @threshold)
begin
	raiserror (''Mirroring unsent_log is greater than the threshold'', 16, 1)
end

drop table #dbmmonitorresults',
	@database_name=N'msdb', 
	@flags=0

exec dbo.sp_update_job @job_name = @job_name, @enabled = 1, @start_step_id = 1

if @recreate = 1
begin
	exec dbo.sp_add_jobschedule @job_name=@job_name,
		@name=@schedule_name,
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=5, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=19900101, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_id=@schedule_id output

	select @job_id job_id, @schedule_id schedule_id
end
else
begin
	select @job_id job_id
end
go