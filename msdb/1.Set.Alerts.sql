use msdb
go

declare @severity int, @alert sysname

set @severity = 16

while @severity <= 25
begin
	set @alert = 'Severity ' + cast(@severity as nvarchar)
	
	exec dbo.sp_add_alert @name = @alert,
		@severity = @severity,
		@enabled = 1,
		@delay_between_responses=60,
		@include_event_description_in=1,
		@category_name=N'[Uncategorized]'

	exec dbo.sp_add_notification @alert_name = @alert,
		@operator_name = N'dba_notify',
		@notification_method = 1

	set @severity = @severity + 1
end
go

-- SQL Server 2012 and above
exec dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1, @databasemail_profile=N'dba_notify_profile', @use_databasemail=1
go

exec dbo.sp_add_alert @name=N'AlwaysOn E983', 
	@message_id=983, 
	@severity=0, 
	@enabled=1, 
	@delay_between_responses=0, 
	@include_event_description_in=0, 
	@category_name=N'[Uncategorized]', 
	@job_id=N'00000000-0000-0000-0000-000000000000'
go

exec dbo.sp_add_alert @name=N'Consistency E823', 
	@message_id=823, 
	@severity=0, 
	@enabled=1, 
	@delay_between_responses=0, 
	@include_event_description_in=0, 
	@category_name=N'[Uncategorized]', 
	@job_id=N'00000000-0000-0000-0000-000000000000'
go

exec dbo.sp_add_alert @name=N'Consistency E824', 
	@message_id=824, 
	@severity=0, 
	@enabled=1, 
	@delay_between_responses=0, 
	@include_event_description_in=0, 
	@category_name=N'[Uncategorized]', 
	@job_id=N'00000000-0000-0000-0000-000000000000'
go

exec dbo.sp_add_alert @name=N'Consistency E825', 
	@message_id=825, 
	@severity=0, 
	@enabled=1, 
	@delay_between_responses=0, 
	@include_event_description_in=0, 
	@category_name=N'[Uncategorized]', 
	@job_id=N'00000000-0000-0000-0000-000000000000'
go

-- Replication alerts. Run on distributor only
/*
exec dbo.sp_update_alert @name=N'Replication: agent failure', @enabled=1
go
exec dbo.sp_add_notification @alert_name=N'Replication: agent failure', @operator_name=N'dba_notify', @notification_method = 1
go

exec dbo.sp_update_alert @name=N'Replication: agent retry', @enabled=1
go
exec dbo.sp_add_notification @alert_name=N'Replication: agent retry', @operator_name=N'dba_notify', @notification_method = 1
go

exec dbo.sp_update_alert @name=N'Replication Warning: Subscription expiration (Threshold: expiration)', @enabled=1
go
exec dbo.sp_add_notification @alert_name=N'Replication Warning: Subscription expiration (Threshold: expiration)', @operator_name=N'dba_notify', @notification_method = 1
go
*/

-- SQL Server 2008
/*
exec master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'UseDatabaseMail', N'REG_DWORD', 1
go
exec master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'DatabaseMailProfile', N'REG_SZ', N'dba_notify_profile'
go
exec msdb.dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1
go
*/