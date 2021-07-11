use msdb
set ansi_nulls on
set quoted_identifier on
go

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Monitoring_CheckLogSize' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Monitoring_CheckLogSize
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Monitoring_CheckLogSize
	@recreate bit = 0
as

set nocount on

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Monitoring_CheckLogSize'
set @schedule_name = 'Schedule' + @job_name
set @description = 't-log size monitoring

created using msdb..job_Monitoring_CheckLogSize stored procedure'
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

set @job_step_id = 0

declare database_cursor cursor fast_forward for
select	[name]
from	sys.databases
where [name] not in ('master', 'model', 'msdb')
	and recovery_model_desc = 'FULL' and is_read_only = 0
order by [name]

open database_cursor

while 1 = 1
begin
	fetch next from database_cursor into @database_name
	if @@fetch_status <> 0
	begin
		if isnull(@job_step_id, 0) <> 0
		begin
			exec dbo.sp_update_jobstep @job_name = @job_name, @step_id = @job_step_id, @on_success_action = 1, @on_fail_action = 1
		end
		break
	end

	set @job_step_id = isnull(@job_step_id, 0) + 1
	set @command = N'exec dbo.sp_add_jobstep @job_name=N''' + @job_name + ''', @step_name=N''' + @database_name + ''', 
		@step_id=' + cast(@job_step_id as nvarchar) + ', 
		@cmdexec_success_code=0,
		@on_success_action=3,
		@on_fail_action=3,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N''TSQL'',
	@command=N''declare @log_space table([database_name] sysname, log_size_MB varchar(4000), log_size_prc varchar(4000), [status] int)
declare @limit float, @backup_log_job_name sysname

set @limit = 16384
set @backup_log_job_name = ''''Maintenance_BackupLogUserDB_withShrink''''

insert	@log_space
exec(''''dbcc sqlperf(logspace)'''')

if exists(	select	1
			from	@log_space
			where [database_name] = ''''' + @database_name + '''''
				and cast(log_size_MB as float) > @limit * 0.9)
begin
	-- check if backup job exists and is not running
	if exists(select 1 from msdb.dbo.sysjobs where [name] = @backup_log_job_name and [enabled] = 1)
		and not exists (select 1 from msdb.dbo.vw_job_run_status where [name] = @backup_log_job_name and run_status = ''''Executing'''')
	begin
		exec msdb..sp_start_job @job_name = @backup_log_job_name
	end
end

if exists(	select	1
			from	@log_space
			where [database_name] = ''''' + @database_name + '''''
				and cast(log_size_MB as float) > @limit)
begin
	raiserror (''''One of the t-log files is too big.'''', 16, 1)
end'',
	@database_name=N''' + @database_name + ''',
	@flags=0'

	exec sp_executesql @command
end

close database_cursor
deallocate database_cursor

exec dbo.sp_update_job @job_name = @job_name, @enabled = 1, @start_step_id = 1

if @recreate = 1
begin
	exec dbo.sp_add_jobschedule @job_name=@job_name,
		@name=@schedule_name,
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=15, 
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