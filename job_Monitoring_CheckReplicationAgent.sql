use msdb
set ansi_nulls on
set quoted_identifier on
go

if not exists(select 1 from sys.databases where [name] = 'distribution')
begin
	raiserror ('Warning, script must be run on a distributor server', 16, 1)
end
go

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Monitoring_CheckReplicationAgent' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Monitoring_CheckReplicationAgent
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Monitoring_CheckReplicationAgent
	@recreate bit = 0
as

set nocount on

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Monitoring_CheckReplicationAgent'
set @schedule_name = 'Schedule' + @job_name
set @description = 'Replication monitoring. It checks distribution and log readers agents status

created using msdb..job_Monitoring_CheckReplicationAgent stored procedure'
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

exec dbo.sp_add_jobstep @job_id=@job_id, @step_name=N'S1', 
	@step_id=1, 
	@cmdexec_success_code=0, 
	@on_success_action=1, 
	@on_fail_action=2, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'set nocount on
go
exec sp_configure ''Ad Hoc Distributed Queries'', 1
go
reconfigure
go
if object_id(''tempdb..##helpjob'') is not null drop table ##helpjob
go
declare @command nvarchar(max)

set @command = ''select * into ##helpjob from openrowset(''''SQLOLEDB'''',''''Server='' + @@servername + '';Database=msdb;Trusted_Connection=yes;'''',''''
set fmtonly off
exec dbo.sp_help_job with result sets 
(
	(
	job_id					uniqueidentifier,
	originating_server		nvarchar(30),
	name					sysname,
	[enabled]				tinyint,
	[description]			nvarchar(512),
	start_step_id			int,
	category				sysname,
	[owner]					sysname,
	notify_level_eventlog	int,
	notify_level_email		int,
	notify_level_netsend	int,
	notify_level_page		int,
	notify_email_operator	sysname,
	notify_netsend_operator	sysname,
	notify_page_operator	sysname,
	delete_level			int,
	date_created			datetime,
	date_modified			datetime,
	version_number			int,
	last_run_date			int,
	last_run_time			int,
	last_run_outcome		int,
	next_run_date			int,
	next_run_time			int,
	next_run_schedule_id	int,
	current_execution_status	int,
	current_execution_step	sysname,
	current_retry_attempt	int,
	has_step				int,
	has_schedule			int,
	has_target				int,
	[type]					int
	)
)'''')''
exec sp_executesql @command
go
if exists(	select	quotename(ss.name) + ''.'' + quotename(a.publisher_db)
			from	dbo.MSdistribution_agents a
					join master.sys.servers ss
					on ss.server_id = a.publisher_id
					join ##helpjob j
					on a.job_id = j.job_id
			where j.current_execution_status = 4 and j.[enabled] = 1)
begin
	raiserror (''One of distribution agent is not running'', 16, 1)
end
go
if exists(	select	quotename(ss.name) + ''.'' + quotename(a.publisher_db)
			from	dbo.MSlogreader_agents a
					join master.sys.servers ss
					on ss.server_id = a.publisher_id
					join ##helpjob j
					on a.job_id = j.job_id
			where j.current_execution_status = 4)
begin
	raiserror (''One of log-reader agent is not running'', 16, 1)
end
go
exec sp_configure ''Ad Hoc Distributed Queries'', 0
go
reconfigure
go',
	@database_name=N'distribution', 
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