use msdb
set ansi_nulls on
set quoted_identifier on
go

/*
Here are two jobs, one for physical and the second for a full check
*/

if not exists (
    select  1
    from    INFORMATION_SCHEMA.TABLES
    where TABLE_NAME = 'DBCCCHECKDB' and TABLE_SCHEMA ='dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	create table dbo.DBCCCHECKDB
	(
		CreateDate datetime not null constraint DF_DBCCCHECKDB__CreateDate default (getdate()),
		Error bigint null,
		[Level] bigint null,
		[State] bigint null,
		MessageText varchar(max) null,
		RepairLevel varchar(max) null,
		[Status] bigint null,
		[DbId] bigint null,
		DbFragId bigint null,
		ObjectId bigint null,
		IndexId bigint null,
		PartitionID bigint null,
		AllocUnitID bigint null,
		RidDbId bigint null,
		RidPruId bigint null,
		[File] bigint null,
		[Page] bigint null,
		Slot bigint null,
		RefDbId bigint null,
		RefPruId bigint null,
		RefFile bigint null,
		RefPage bigint null,
		RefSlot bigint null,
		Allocation bigint null
	)

	create clustered index IXC_DBCCCHECKDB__CreateDate on dbo.DBCCCHECKDB (CreateDate) with (data_compression = page)
end
go

if exists (
    select  1
    from    INFORMATION_SCHEMA.VIEWS
    where TABLE_NAME = 'vw_DBCCCHECKDB' and TABLE_SCHEMA ='dbo')
begin
	drop view dbo.vw_DBCCCHECKDB
end
go

create view dbo.vw_DBCCCHECKDB
as
select	db_name([DbId]) [db_name],
		object_name(ObjectId, [DbId]) [object_name],
		*
from	dbo.DBCCCHECKDB
go

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Maintenance_CheckDbPhy' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Maintenance_CheckDbPhy
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Maintenance_CheckDbPhy
	@recreate bit = 0
as

set nocount on

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Maintenance_CheckDbPhy'
set @schedule_name = 'Schedule' + @job_name
set @description = 'DBCC CHECKDB with PHYSICAL_ONLY option'
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

exec dbo.sp_add_jobstep @job_id = @job_id, @step_name=N'S1', 
	@step_id=1, 
	@cmdexec_success_code=0, 
	@on_success_action=1, 
	@on_fail_action=2, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'set nocount on
create table #dbcc
(
	Error bigint null,
	[Level] bigint null,
	[State] bigint null,
	MessageText varchar(max) null,
	RepairLevel varchar(max) null,
	[Status] bigint null,
	[DbId] bigint null,
	DbFragId bigint null,
	ObjectId bigint null,
	IndexId bigint null,
	PartitionID bigint null,
	AllocUnitID bigint null,
	RidDbId bigint null,
	RidPruId bigint null,
	[File] bigint null,
	[Page] bigint null,
	Slot bigint null,
	RefDbId bigint null,
	RefPruId bigint null,
	RefFile bigint null,
	RefPage bigint null,
	RefSlot bigint null,
	Allocation bigint null
)

declare @database_name sysname, @command nvarchar(4000)

declare database_cursor cursor fast_forward for
select	[name]
from	[master].sys.databases
where state_desc = ''ONLINE'' and [name] not in (''tempdb'')
order by [name]

open database_cursor

while 1 = 1
begin
	fetch next from database_cursor into @database_name
	if @@fetch_status <> 0 break

	set @command = ''dbcc checkdb('''''' + (@database_name) + '''''') with no_infomsgs, physical_only, tableresults''
	insert	#dbcc
	exec (@command)

	insert	dbo.DBCCCHECKDB
			(Error
			,[Level]
			,[State]
			,MessageText
			,RepairLevel
			,[Status]
			,[DbId]
			,DbFragId
			,ObjectId
			,IndexId
			,PartitionID
			,AllocUnitID
			,RidDbId
			,RidPruId
			,[File]
			,[Page]
			,Slot
			,RefDbId
			,RefPruId
			,RefFile
			,RefPage
			,RefSlot
			,Allocation)
	select	Error
			,[Level]
			,[State]
			,MessageText
			,RepairLevel
			,[Status]
			,[DbId]
			,DbFragId
			,ObjectId
			,IndexId
			,PartitionID
			,AllocUnitID
			,RidDbId
			,RidPruId
			,[File]
			,[Page]
			,Slot
			,RefDbId
			,RefPruId
			,RefFile
			,RefPage
			,RefSlot
			,Allocation
	from	#dbcc

	if exists(select 1 from #dbcc where RepairLevel is not null)
	begin
		raiserror (''dbcc checkdb failed'', 16, 1)
	end

	truncate table #dbcc
end

close database_cursor
deallocate database_cursor

drop table #dbcc',
	@database_name=N'msdb', 
	@flags=0

exec dbo.sp_update_job @job_name = @job_name, @enabled = 1, @start_step_id = 1

if @recreate = 1
begin
	exec dbo.sp_add_jobschedule @job_id=@job_id, @name=N'ScheduleMaintenance_CheckDbPhy1', 
		@enabled=1, 
		@freq_type=32, 
		@freq_interval=7, 
		@freq_subday_type=1, 
		@freq_subday_interval=15, 
		@freq_relative_interval=1, 
		@freq_recurrence_factor=1, 
		@active_start_date=19900101, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959

	exec dbo.sp_add_jobschedule @job_id=@job_id, @name=N'ScheduleMaintenance_CheckDbPhy2', 
		@enabled=1, 
		@freq_type=32, 
		@freq_interval=7, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=2, 
		@freq_recurrence_factor=1, 
		@active_start_date=19900101, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959

	exec dbo.sp_add_jobschedule @job_id=@job_id, @name=N'ScheduleMaintenance_CheckDbPhy3', 
		@enabled=1, 
		@freq_type=32, 
		@freq_interval=7, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=4, 
		@freq_recurrence_factor=1, 
		@active_start_date=19900101, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
end

select @job_id job_id
go

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Maintenance_CheckDbFull' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Maintenance_CheckDbFull
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Maintenance_CheckDbFull
	@recreate bit = 0
as

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Maintenance_CheckDbFull'
set @schedule_name = 'Schedule' + @job_name
set @description = 'DBCC CHECKDB full check'
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

exec dbo.sp_add_jobstep @job_id = @job_id, @step_name=N'S1', 
	@step_id=1, 
	@cmdexec_success_code=0, 
	@on_success_action=1, 
	@on_fail_action=2, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'set nocount on
create table #dbcc
(
	Error bigint null,
	[Level] bigint null,
	[State] bigint null,
	MessageText varchar(max) null,
	RepairLevel varchar(max) null,
	[Status] bigint null,
	[DbId] bigint null,
	DbFragId bigint null,
	ObjectId bigint null,
	IndexId bigint null,
	PartitionID bigint null,
	AllocUnitID bigint null,
	RidDbId bigint null,
	RidPruId bigint null,
	[File] bigint null,
	[Page] bigint null,
	Slot bigint null,
	RefDbId bigint null,
	RefPruId bigint null,
	RefFile bigint null,
	RefPage bigint null,
	RefSlot bigint null,
	Allocation bigint null
)

declare @database_name sysname, @command nvarchar(4000)

declare database_cursor cursor fast_forward for
select	[name]
from	[master].sys.databases
where state_desc = ''ONLINE'' and [name] not in (''tempdb'')
order by [name]

open database_cursor

while 1 = 1
begin
	fetch next from database_cursor into @database_name
	if @@fetch_status <> 0 break

	set @command = ''dbcc checkdb('''''' + (@database_name) + '''''') with no_infomsgs, tableresults''
	insert	#dbcc
	exec (@command)

	insert	dbo.DBCCCHECKDB
			(Error
			,[Level]
			,[State]
			,MessageText
			,RepairLevel
			,[Status]
			,[DbId]
			,DbFragId
			,ObjectId
			,IndexId
			,PartitionID
			,AllocUnitID
			,RidDbId
			,RidPruId
			,[File]
			,[Page]
			,Slot
			,RefDbId
			,RefPruId
			,RefFile
			,RefPage
			,RefSlot
			,Allocation)
	select	Error
			,[Level]
			,[State]
			,MessageText
			,RepairLevel
			,[Status]
			,[DbId]
			,DbFragId
			,ObjectId
			,IndexId
			,PartitionID
			,AllocUnitID
			,RidDbId
			,RidPruId
			,[File]
			,[Page]
			,Slot
			,RefDbId
			,RefPruId
			,RefFile
			,RefPage
			,RefSlot
			,Allocation
	from	#dbcc

	if exists(select 1 from #dbcc where RepairLevel is not null)
	begin
		raiserror (''dbcc checkdb failed'', 16, 1)
	end

	truncate table #dbcc
end

close database_cursor
deallocate database_cursor

drop table #dbcc',
	@database_name=N'msdb', 
	@flags=0

exec dbo.sp_update_job @job_name = @job_name, @enabled = 1, @start_step_id = 1

if @recreate = 1
begin
	exec dbo.sp_add_jobschedule @job_id=@job_id, @name=N'ScheduleMaintenance_CheckDbFull', 
		@enabled=1, 
		@freq_type=32, 
		@freq_interval=7, 
		@freq_subday_type=1, 
		@freq_subday_interval=15, 
		@freq_relative_interval=8, 
		@freq_recurrence_factor=1, 
		@active_start_date=19900101, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
end

select @job_id job_id
go