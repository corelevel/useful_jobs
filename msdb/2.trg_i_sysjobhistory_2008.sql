/*
Trigger for SQL Server 2008/2008R2. With mirroring support.

Before use, set default Database Mail profile. Check with:
exec msdb.dbo.sysmail_help_principalprofile_sp
is_default must be equal 1
*/
use [msdb]
set ansi_nulls on
set quoted_identifier on
go

if exists (select 1 from sys.triggers where [name] = 'trg_i_sysjobhistory' and parent_id = object_id('dbo.sysjobhistory'))
begin
    drop trigger dbo.trg_i_sysjobhistory
end
go

/*
A long time ago, created by github.com/corelevel
*/
create trigger dbo.trg_i_sysjobhistory on dbo.sysjobhistory
for insert
as

set nocount on

declare @email_body nvarchar(max), @email_subject nvarchar(255), @email_recipient varchar(max)
declare @error_message nvarchar(4000)

begin try
	if exists (select 1 from inserted where run_status = 0 and step_name <> '(job outcome)')
	begin
		select	@email_body = 'Dear friend, for further information please check job history. First error was:' + char(10) + char(13) + i.[message],
				@email_subject = N'SQL Server Job System: ''' + jo.[name] + N''' partially failed on ' + @@servername,
				@email_recipient = op.email_address
		from	inserted i
				join dbo.sysjobs jo
				on jo.job_id = i.job_id
				join dbo.sysoperators op
				on op.id = jo.notify_page_operator_id	-- pager
				--on op.id = jo.notify_email_operator_id	-- email
		where i.run_status = 0
			-- did we generate an alert before the current step?
			and not exists
			(
				select	1
				from	dbo.sysjobhistory jh
				where jh.job_id = i.job_id and jh.step_id <> i.step_id and jh.run_status = 0
					and jh.instance_id >= (select max(jh_.instance_id) from dbo.sysjobhistory jh_ where jh_.job_id = i.job_id and jh_.step_id = 1)
					and not exists
					(
					select	1
					from	dbo.sysjobsteps js
							join sys.database_mirroring mi
							on mi.database_id = db_id(js.[database_name])
					where js.job_id = jh.job_id and js.step_id = jh.step_id and mi.mirroring_role_desc = 'MIRROR'
					)
			)
			-- is database mirror?
			and not exists
			(
			select	1
			from	dbo.sysjobsteps js
					join sys.database_mirroring mi
					on mi.database_id = db_id(js.[database_name])
			where js.job_id = i.job_id and js.step_id = i.step_id and mi.mirroring_role_desc = 'MIRROR'
			)

		if @@rowcount > 0
		begin
			--Email
			exec dbo.sp_send_dbmail @recipients = @email_recipient, @body = @email_body, @subject = @email_subject
			--Windows event log
			--exec xp_logevent 55000, @email_subject, 'error'
		end
	end
end try
begin catch
	-- Enable for debugging only
	--set @error_message = error_message()
	--exec xp_logevent 55000, @email_subject, 'error'
end catch
go
