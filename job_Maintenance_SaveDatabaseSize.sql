use msdb
set ansi_nulls on
set quoted_identifier on
go

if not exists (
    select  1
    from    INFORMATION_SCHEMA.TABLES
    where TABLE_NAME = 'DatabaseSize' and TABLE_SCHEMA ='dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	create table dbo.DatabaseSize
	(
	create_date		date not null,
	[database_name]	sysname not null,
	[file]			varchar(500) not null,
	size			decimal(18,2) not null, -- in GB
	[type]			tinyint not null
	)
	create clustered index IXC_DatabaseSize__create_date_database_name on dbo.DatabaseSize (create_date, [database_name]) with (data_compression = page)
end

if exists(	select	1
			from	INFORMATION_SCHEMA.ROUTINES
			where ROUTINE_NAME = 'job_Maintenance_SaveDatabaseSize' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	drop procedure dbo.job_Maintenance_SaveDatabaseSize
end
go

/*
A long time ago, created by github.com/corelevel
*/
create procedure dbo.job_Maintenance_SaveDatabaseSize
	@recreate bit = 0
as

set nocount on

declare @job_name sysname, @description sysname, @operator sysname, @schedule_name sysname, @database_name sysname
declare @job_id uniqueidentifier, @job_step_id int, @schedule_id int
declare @command nvarchar(4000)

set @job_name = 'Maintenance_SaveDatabaseSize'
set @schedule_name = 'Schedule' + @job_name
set @description = 'Save database size'
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
	@on_fail_action=1, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'set nocount on
insert	dbo.DatabaseSize(create_date, [database_name], [file], size, [type])
select	getdate() create_date,
		db.name [database_name],
		fi.physical_name [file],
		fi.size * 8.0 / (1024.0 * 1024.0) size,
		fi.[type]
from	sys.master_files fi
		join sys.databases db
		on db.database_id = fi.database_id
where not exists(select 1 from dbo.DatabaseSize ds where ds.create_date = cast(getdate() as date) and ds.[database_name] = db.[name])
	and db.[name] not in (''tempdb'', ''model'')
',
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
		@freq_subday_type=1,
		@freq_subday_interval=1,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=19900101,
		@active_end_date=99991231,
		@active_start_time=700,
		@active_end_time=235959,
		@schedule_id=@schedule_id output

	select @job_id job_id, @schedule_id schedule_id
end
else
begin
	select @job_id job_id
end
go

/*
declare @From date

set @From = '2017-12-22'

select	[database_name],
		minD.create_date [From],
		maxD.create_date [To],
		maxD.Size - minD.Size Increment
from	(select distinct [database_name] from dbo.DatabaseSize) db
		outer apply
		(
		select	sum(Size) Size,
				create_date
		from	dbo.DatabaseSize db_
		where db_.[database_name] = db.[database_name] and db_.[Type] = 0
			and db_.create_date =
			(
			select	max(create_date)
			from	dbo.DatabaseSize
			where [database_name] = db.[database_name] and [Type] = 0
			--	and create_date > @From
			group by [database_name]
			)
		group by db_.create_date
		) maxD
		outer apply
		(
		select	sum(Size) Size,
				create_date
		from	dbo.DatabaseSize db_
		where db_.[database_name] = db.[database_name] and db_.[Type] = 0
			and db_.create_date =
			(
			select	min(create_date)
			from	dbo.DatabaseSize
			where [database_name] = db.[database_name] and [Type] = 0
			--	and create_date > @From
			group by [database_name]
			)
		group by db_.create_date
		) minD
where [database_name] not in ('master', 'model', 'msdb', 'tempdb')
order by Increment desc

select	[database_name],
		[Month],
		minD.create_date [From],
		maxD.create_date [To],
		replace(cast(maxD.Size - minD.Size as varchar(4000)), '.', ',') Increment
from	(select distinct [database_name], datepart(month, create_date) [Month] from dbo.DatabaseSize where create_date >= '2017-01-01' and create_date < '2018-01-01') db
		outer apply
		(
		select	sum(Size) Size,
				create_date
		from	dbo.DatabaseSize db_
		where db_.[database_name] = db.[database_name] and db_.[Type] = 0
			and db_.create_date =
			(
			select	max(create_date)
			from	dbo.DatabaseSize
			where [database_name] = db.[database_name] and [Type] = 0
				and datepart(month, create_date) = db.[Month]
			group by [database_name]
			)
		group by db_.create_date
		) maxD
		outer apply
		(
		select	sum(Size) Size,
				create_date
		from	dbo.DatabaseSize db_
		where db_.[database_name] = db.[database_name] and db_.[Type] = 0
			and db_.create_date =
			(
			select	min(create_date)
			from	dbo.DatabaseSize
			where [database_name] = db.[database_name] and [Type] = 0
				and datepart(month, create_date) = db.[Month]
			group by [database_name]
			)
		group by db_.create_date
		) minD
where [database_name] not in ('master', 'model', 'msdb', 'tempdb')
order by [database_name], [Month]
*/