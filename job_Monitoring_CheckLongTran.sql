use msdb
set ansi_nulls on
set quoted_identifier on
go

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Monitoring_CheckLongTran' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Monitoring_CheckLongTran
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Monitoring_CheckLongTran
	@recreate bit = 0
as

set nocount on

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Monitoring_CheckLongTran'
set @schedule_name = 'Schedule' + @job_name
set @description = 'Long running transaction monitoring

created using msdb..job_Monitoring_CheckLongTran stored procedure'
set @operator = 'dba_notify'

if @recreate = 1
begin
	if exists(select 1 from dbo.sysjobs where [name] = @job_name)
	begin
		exec msdb.dbo.sp_delete_job @job_name=@job_name
	end

	exec dbo.sp_add_job @job_name=@job_name,@enabled=1,@notify_level_eventlog=0,@notify_level_email=2,@notify_level_netsend=2,@notify_level_page=2,@delete_level=0,@description=@description,@owner_login_name=N'sa',@notify_page_operator_name=@operator,@job_id=@job_id output
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

exec dbo.sp_add_jobstep @job_id=@job_id, @step_name=N'tran', 
	@step_id=1, 
	@cmdexec_success_code=0, 
	@on_success_action=3, 
	@on_success_step_id=0, 
	@on_fail_action=2, 
	@on_fail_step_id=0, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'if exists(
	select	ses.session_id,
			ses.login_name,
			db_name(ses.database_id) [db_name],
			ses.[host_name],
			ses.[program_name],
			ac.transaction_begin_time,
			datediff(second, ac.transaction_begin_time, getdate()) duration_sec,
			query.[text],
			eplan.query_plan
	from	sys.dm_tran_session_transactions st
			join sys.dm_exec_sessions ses
			on ses.session_id = st.session_id 
			join sys.dm_tran_active_transactions ac
			on ac.transaction_id = st.transaction_id
			left join sys.dm_exec_requests req
			on req.session_id = ses.session_id
			outer apply sys.dm_exec_sql_text(req.[sql_handle]) query
			outer apply sys.dm_exec_query_plan(req.plan_handle) eplan
	where datediff(second, ac.transaction_begin_time, getdate()) > 60 * 5)
begin
	raiserror (''Long running uncommitted transaction detected'', 16, 1)
end', 
		@database_name=N'master', 
		@flags=0

exec dbo.sp_add_jobstep @job_id=@job_id, @step_name=N'snapshot tran', 
	@step_id=2, 
	@cmdexec_success_code=0, 
	@on_success_action=1, 
	@on_success_step_id=0, 
	@on_fail_action=2, 
	@on_fail_step_id=0, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'if exists(
	select	ses.session_id,
			ses.login_name,
			db_name(ses.database_id) [db_name],
			ses.[host_name],
			ses.[program_name],
			sst.elapsed_time_seconds,
			req.open_transaction_count,
			query.[text],
			eplan.query_plan
	from	sys.dm_tran_active_snapshot_database_transactions sst
			join sys.dm_exec_sessions ses
			on ses.session_id = sst.session_id
			left join sys.dm_exec_requests req
			on req.session_id = ses.session_id
			outer apply sys.dm_exec_sql_text(req.[sql_handle]) query
			outer apply sys.dm_exec_query_plan(req.plan_handle) eplan
	where sst.elapsed_time_seconds > 60 * 5)
begin
	raiserror (''Long running snapshot transaction detected'', 16, 1)
end', 
		@database_name=N'master', 
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