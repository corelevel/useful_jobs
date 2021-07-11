exec sp_configure 'Database Mail XPs', 1
go
reconfigure
go
use msdb

declare @profile_name sysname, @account_name sysname, @mailserver_name sysname
declare @email_address_from sysname, @email_address_to nvarchar(100)

set @profile_name = 'dba_notify_profile'
set @account_name = 'dba_notify_account'

set @mailserver_name = null		-- your SMTP server address
set @email_address_from = null	-- I prefer to use this template: replace(@@servername, '\', '~') + '@YOUR_DOMAIN'
set @email_address_to = null	-- operator's email

if @mailserver_name is not null and @email_address_from is not null and @email_address_to is not null
begin
	exec dbo.sysmail_add_profile_sp @profile_name = @profile_name

	exec dbo.sysmail_add_account_sp
		@account_name = @account_name,
		@email_address = @email_address_from,
		@mailserver_name = @mailserver_name

	exec dbo.sysmail_add_profileaccount_sp
		@profile_name = @profile_name,
		@account_name = @account_name,
		@sequence_number =1

	exec dbo.sysmail_add_principalprofile_sp
		@profile_name = @profile_name,
		@principal_name = 'public',
		@is_default = 1

	exec dbo.sp_add_operator @name=N'dba_notify', 
		@enabled=1, 
		@weekday_pager_start_time=90000, 
		@weekday_pager_end_time=180000, 
		@saturday_pager_start_time=90000, 
		@saturday_pager_end_time=180000, 
		@sunday_pager_start_time=90000, 
		@sunday_pager_end_time=180000, 
		@pager_days=0, 
		@email_address=@email_address_to, 
		@category_name=N'[Uncategorized]'
end
else
begin
	raiserror ('Please specify all mandatory parameters', 16, 1)
end
go