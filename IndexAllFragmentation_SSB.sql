use DBAWORK
go

--requirements
--ola installed to master
--sp_whoisactive to master
--mail configured
--sp_foreachdb to master

--select top 1 * from DBAWORK.[dbo].[tb_Performance_Monitoring_Version] order by Date DESC  --current version

--drop existing stored procs
if exists (select * from sys.objects where name = 'bp_index_frag_history' and type = 'p')
    drop procedure bp_index_frag_history
GO

if exists (select * from sys.objects where name = 'bp_io_performance' and type = 'p')
    drop procedure bp_io_performance
GO

if exists (select * from sys.objects where name = 'bp_long_run_SP' and type = 'p')
    drop procedure bp_long_run_SP
GO

if exists (select * from sys.objects where name = 'bp_cpu_utilization' and type = 'p')
    drop procedure bp_cpu_utilization
GO

if exists (select * from sys.objects where name = 'bp_Index_Rebuild_Targeted' and type = 'p')
    drop procedure bp_Index_Rebuild_Targeted
GO

if exists (select * from sys.objects where name = 'bp_Stat_Rebuild_Targeted' and type = 'p')
    drop procedure bp_Stat_Rebuild_Targeted
GO

/*version information
1/3/18	 5.00	Add Parameter table and point SPs to there for information, cleanup for release to share to put all in one SP
3/20/18  5.01   Add vw_Unused_Tables
4/12/18	 5.02	Add bp_Stat_Rebuild_Targeted, spelling changed in SP from Targetted to Targeted
*/

--create tables if needed in DBAWORK
Use DBAWORK
GO

/*if database name has space or - in name replace sp_MSforeachdb with sp_foreachdb and install sp_foreachdb.sql except for top tables 
(6/20/17 looks like change for all now) and change job to report success on failure
  servers that currently have sp_MSforeachdb; only need to change in IndexAllFragmentation
  --DC1-DAXDEVDB02, no longer special as of 6/21/17
  DC1-ITDB01, 6/21/17 ran fine with no change
  MK-QUESTSQL
  MK-TFS02  
  Report Servers need to be adjusted in CPUUtilization
  AWS RDS Job History in CPUUtilization does not work
*/

/*sp detail to use for word analysis in R, needs to be added to each database
CREATE VIEW [dbo].[vw_SP_Create_Scripts]
AS
SELECT        O.name AS ProcName, CAST(LTRIM(RTRIM(M.definition)) AS text) AS CreateScript, CAST(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(M.definition)), CHAR(10), ''), CHAR(13), ''), CHAR(9), '') AS text) AS R_CreateScript, 
                         O.create_date, O.modify_date
FROM            sys.sql_modules AS M INNER JOIN
                         sys.objects AS O ON M.object_id = O.object_id
WHERE        (O.type IN ('P')) AND (LEFT(O.name, 8) NOT IN ('sp_MSupd', 'sp_MSins', 'sp_MSdel'))
GO
*/

--add version information
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Performance_Monitoring_Version]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Performance_Monitoring_Version](
	[Version] [nvarchar](10) NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Version] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

INSERT INTO [dbo].[tb_Performance_Monitoring_Version] ([Version],[Date])
     VALUES ('5.02',getdate())


--add tables
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Jobs_hx]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Jobs_hx](
	[row_id] [int] IDENTITY(1,1) NOT NULL,
	[JobName] [nvarchar](150) NULL,
	[JobFailStep] [int] NULL,
	[JobFailMessage] [varchar](max) NULL,
	[RunDateTime] [datetime] NULL,
	[JobDurationSeconds] [int] NULL,
	[RunStatus] [int] NULL,
	[owner] [nvarchar](200) NULL,
	[source] [nvarchar](20) NULL,
	[Date] [datetime] NULL,
 CONSTRAINT [pk_ID_Jobs] PRIMARY KEY CLUSTERED 
(
	[row_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_Jobs_hx_JobFailStep' AND object_id = OBJECT_ID('tb_Jobs_hx'))
CREATE INDEX [idx_tb_Jobs_hx_JobFailStep] ON [DBAWORK].[dbo].[tb_Jobs_hx] ([JobFailStep]) 
INCLUDE ([JobName], [JobDurationSeconds], [RunStatus], [owner], [Date])
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_errors]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_errors](
	[Date] [datetime] NULL,
	[TableName] [nvarchar](50) NULL,
	[Message] [nvarchar](250) NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Errors] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Fragmentation_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Fragmentation_History](
	[DB_Name] [nvarchar](500) NULL,
	[Table_Name] [nvarchar](500) NULL,
	[Index_ID] [int] NULL,
	[Index_Name] [nvarchar](1000) NULL,
	[Avg_Fragmentation] [decimal](4, 1) NULL,
	[Date] [datetime] NULL,
	[page_count] [bigint] NULL,
	[partition_number] [int] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Fragment] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Statistics_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Statistics_History](
	[DB_Name] [nvarchar](500) NULL,
	[Table_Name] [nvarchar](500) NULL,
	[Index_Name] [nvarchar](1000) NULL,
	[LastUpdateDate] [datetime] NULL,
	[rowmodctr] [decimal](16, 0) NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Stats] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Most_Used_Table_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Most_Used_Table_History](
	[DatabaseName] [nvarchar](500) NULL,
	[TableName] [nvarchar](500) NULL,
	[TotalAccesses] [decimal](18, 0) NULL,
	[TotalWrites] [decimal](18, 0) NULL,
	[PercentAccessesAreWrites] [decimal](5, 2) NULL,
	[TotalReads] [decimal](18, 0) NULL,
	[PercentAccessesAreReads] [decimal](5, 2) NULL,
	[ReadSeeks] [decimal](18, 0) NULL,
	[PercentReadsAreIndexSeeks] [decimal](5, 2) NULL,
	[ReadScans] [decimal](18, 0) NULL,
	[PercentReadsAreIndexScans] [decimal](5, 2) NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_MostUsedTbl] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_Most_Used_Table_History_Date' AND object_id = OBJECT_ID('tb_Most_Used_Table_History'))
CREATE INDEX [idx_tb_Most_Used_Table_History_Date] ON [DBAWORK].[dbo].[tb_Most_Used_Table_History] ([Date]) 
INCLUDE ([DatabaseName], [TableName], [TotalAccesses])
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Stored_Procedure_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Stored_Procedure_History](
	[DB_Name] [nvarchar](500) NULL,
	[SP_Name] [nvarchar](500) NULL,
	[Create_Date] [datetime] NULL,
	[Modify_Date] [datetime] NULL,
	[Execution_Count] [decimal](18, 0) NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_SP] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Index_Usage_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Index_Usage_History](
	[DB_Name] [nvarchar](500) NULL,
	[Table_Name] [nvarchar](500) NULL,
	[Index_Name] [nvarchar](500) NULL,
	[user_seeks] [decimal](18, 0) NULL,
	[user_scans] [decimal](18, 0) NULL,
	[user_lookups] [decimal](18, 0) NULL,
	[user_updates] [decimal](18, 0) NULL,
	[last_user_seek] [datetime] NULL,
	[last_user_scan] [datetime] NULL,
	[last_user_lookup] [datetime] NULL,
	[last_user_update] [datetime] NULL,
	[type_desc] [nvarchar](500) NULL,
	[fill_factor] [decimal](18, 0) NULL,
	[is_primary_key] [bit] NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_IndexUse] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Stored_Procedure_Execution_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Stored_Procedure_Execution_History](
	[DB_Name] [nvarchar](250) NULL,
	[SP Name] [sysname] NOT NULL,
	[execution_count] [bigint] NOT NULL,
	[Calls/Second] [bigint] NOT NULL,
	[AvgWorkerTime] [bigint] NULL,
	[TotalWorkerTime] [bigint] NOT NULL,
	[total_elapsed_time] [bigint] NOT NULL,
	[avg_elapsed_time] [bigint] NULL,
	[cached_time] [datetime] NULL,
	[TotalLogicalReads] [bigint] NOT NULL,
	[AvgLogicalReads] [bigint] NULL,
	[TotalLogicalWrites] [bigint] NOT NULL,
	[AvgLogicalWrites] [bigint] NULL,
	[Date] [datetime] NOT NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_SPExec] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_Stored_Procedure_Execution_History_avg_elapsed_time' AND object_id = OBJECT_ID('tb_Stored_Procedure_Execution_History'))
CREATE NONCLUSTERED INDEX [idx_tb_Stored_Procedure_Execution_History_avg_elapsed_time] ON [dbo].[tb_Stored_Procedure_Execution_History]
(
	[avg_elapsed_time] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_Stored_Procedure_Execution_History_Name_time' AND object_id = OBJECT_ID('tb_Stored_Procedure_Execution_History'))
CREATE NONCLUSTERED INDEX [idx_tb_Stored_Procedure_Execution_History_Name_time]
ON [dbo].[tb_Stored_Procedure_Execution_History] ([DB_Name],[SP Name])
INCLUDE ([avg_elapsed_time])
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Index_Free_Space]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Index_Free_Space](
	[DB_Name] [nvarchar](500) NULL,
	[Table_Name] [nvarchar](500) NULL,
	[Index_ID] [int] NULL,
	[Index_Name] [nvarchar](1000) NULL,
	[Type] [nvarchar](50) NULL,
	[Total_MBs] [int] NULL,
	[Free_Space_MBs] [int] NULL,
	[Free_Space_Percent] [decimal](4, 1) NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_IndexFree] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Table_Rows]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Table_Rows](
	[DatabaseName] [nvarchar](500) NULL,
	[TableNameFull] [nvarchar](500) NULL,
	[TableName] [nvarchar](500) NULL,
	[RowCount] [bigint] NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_TblRows] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_Table_Rows_Date' AND object_id = OBJECT_ID('tb_Table_Rows'))
CREATE INDEX [idx_tb_Table_Rows_Date] ON [DBAWORK].[dbo].[tb_Table_Rows] ([Date]) 
INCLUDE ([DatabaseName], [TableName], [RowCount])
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Buffer_Cache_Hit_Ratio]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Buffer_Cache_Hit_Ratio](
	[Buffer_Cache_Hit_Ratio] [decimal](5, 3) NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Buffer] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Parameters]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Parameters](
	[Item] [nvarchar](250) NULL,
	[SP_Name] [nvarchar](250) NULL,
	[Class] [nvarchar](250) NULL,
	[Date] [datetime] NOT NULL DEFAULT(GETDATE()),
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Parameters] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'trg_UpdateDate') AND TYPE IN (N'TR'))
EXEC dbo.sp_executesql @statement = N'
CREATE TRIGGER trg_UpdateDate
ON DBAWORK.dbo.tb_Parameters
AFTER UPDATE
AS
    UPDATE DBAWORK.dbo.tb_Parameters
    SET Date = GETDATE()
    WHERE ID IN (SELECT DISTINCT ID FROM Inserted)'

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Top_Queries_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Top_Queries_History](
	[name] [nvarchar](128) NULL,
	[DB_Name] [nvarchar](250) NULL,
	[execution_count] [bigint] NOT NULL,
	[total_logical_reads] [bigint] NOT NULL,
	[last_logical_reads] [bigint] NOT NULL,
	[total_logical_writes] [bigint] NOT NULL,
	[last_logical_writes] [bigint] NOT NULL,
	[total_elapsed_time_in_S] [bigint] NULL,
	[last_elapsed_time_in_S] [bigint] NULL,
	[AvgExecutionDuration1000sOfSeconds] [bigint] NULL,
	[AvgPhysicalReads] [bigint] NOT NULL,
	[MinPhysicalReads] [bigint] NOT NULL,
	[MaxPhysicalReads] [bigint] NOT NULL,
	[AvgPhysicalReads_kbsize] [bigint] NULL,
	[MinPhysicalReads_kbsize] [bigint] NULL,
	[MaxPhysicalReads_kbsize] [bigint] NULL,
	[CreationDateTime] [datetime] NOT NULL,
	[last_execution_time] [datetime] NOT NULL,
	[query_text] [nvarchar](max) NULL,
	[query_plan] [xml] NULL,
	[missing_index_info] [bit] NULL,
	[Date] [datetime] NOT NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Qrys] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_Top_Queries_History_AvgExecutionDuration' AND object_id = OBJECT_ID('tb_Top_Queries_History'))
CREATE NONCLUSTERED INDEX [idx_tb_Top_Queries_History_AvgExecutionDuration] ON [dbo].[tb_Top_Queries_History]
(	[AvgExecutionDuration1000sOfSeconds] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_distribution_commands]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_distribution_commands](
	[name] [nvarchar](100) NOT NULL,
	[id] [int] NOT NULL,
	[start_time] [datetime] NOT NULL,
	[runstatus] [int] NOT NULL,
	[time] [datetime] NOT NULL,
	[delivered_commands] [int] NOT NULL,
	[seconds] [int] NULL,
	[commands] [int] NULL,
	[commands_per_Minute] [int] NULL,
	[DateKey] [int] NULL,
	[Hour] [int] NULL,
	[Minute] [int] NULL,
	[distID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_distID] PRIMARY KEY CLUSTERED 
(
	[distID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_lock_history]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_lock_history](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[spid] [int] NULL,
	[dbid] [int] NULL,
	[objId] [int] NULL,
	[indId] [int] NULL,
	[Type] [char](4) NULL,
	[resource] [nchar](32) NULL,
	[Mode] [char](8) NULL,
	[status] [char](6) NULL,
	blocking_session_id [int] NULL,
	[text] varchar(8000) null,
	[host_name] varchar(128) null,
	[program_name] varchar(128) null,
	[login_name] varchar(128) null,	
	[login_time] datetime null,
	[DateTime] [datetime] NULL,
	 CONSTRAINT [pk_ID_lock_history] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_monitor_sql_database_performance_hx]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_monitor_sql_database_performance_hx](
	[serID] [int] NOT NULL,
	[dbID] [int] NOT NULL,
	[database_drive] [varchar](1) NULL,
	[database_file_name] [nvarchar](160) NULL,
	[NumberReads] [bigint] NULL,
	[NumberWrites] [bigint] NULL,
	[TotalIO] [bigint] NULL,
	[MBsRead] [bigint] NULL,
	[MBsWritten] [bigint] NULL,
	[TotalMBs] [bigint] NULL,
	[IoStallReadMS] [bigint] NULL,
	[IoStallWriteMS] [bigint] NULL,
	[IoStallMS] [bigint] NULL,
	[AvgStallPerReadIO] [bigint] NULL,
	[AvgStallPerWriteIO] [bigint] NULL,
	[AvgStallPerIO] [bigint] NULL,
	[report_date_time_start] [datetime] NULL,
	[report_date_time_end] [datetime] NULL,
	[TimeStamp] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_IO] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_tb_monitor_sql_database_performance_hx_primary' AND object_id = OBJECT_ID('tb_monitor_sql_database_performance_hx'))
CREATE INDEX [idx_tb_monitor_sql_database_performance_hx_primary] 
ON [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx] ([serID], [dbID], [database_drive], [database_file_name])
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Servers]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Servers](
	[serID] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[server_name] [nvarchar](50) NULL,
	[instance_name] [nvarchar](50) NULL,
	[server_type] [nvarchar](4) NULL,
	[use_category] [nvarchar](5) NULL,
	[ip_address] [nvarchar](15) NULL,
	[sql_version_num] [nvarchar](25) NULL,
	[sql_version] [nvarchar](30) NULL,
	[sql_edition] [nvarchar](33) NULL,
	[sql_physical_cpus] [int] NULL,
	[sql_logical_cpus] [int] NULL,
	[license_type] [nvarchar](25) NULL,
	[description] [nvarchar](100) NULL,
	[location_physical] [nvarchar](100) NULL,
	[it_owner] [nvarchar](50) NULL,
	[business_owner] [nvarchar](50) NULL,
	[virtual] [bit] NULL,
	[active] [bit] NULL,
	[build_date] [datetime] NULL,
	[decommision_date] [datetime] NULL,
	[line_of_business] [nvarchar](50) NULL,
	[sensitive_data] [bit] NULL,
	[windows_version_num] [nvarchar](25) NULL,
	[Avamar] [bit] NULL,
	[daily_check] [bit] NULL,
	[SQL_not_running] [bit] NULL,
	[Delta_Monitored] [bit] NULL,
	[Divestiture] [bit] NULL,
	[sql_service_name] [nvarchar](40) NULL,
	[sql_agent_service_name] [nvarchar](40) NULL,
	[special_monitor] [bit] NULL,
	[AvailableRAM] [int] NULL,
	[MaxSQLRAM] [int] NULL,
 CONSTRAINT [pk_ID_serID] PRIMARY KEY CLUSTERED 
(
	[serID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Servers_Databases]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Servers_Databases](
	[dbID] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[serID] [int] NULL,
	[server_name] [nvarchar](50) NULL,
	[database_name] [nvarchar](150) NULL,
	[description] [nvarchar](100) NULL,
	[it_owner] [nvarchar](50) NULL,
	[business_owner] [nvarchar](50) NULL,
	[active] [bit] NULL,
	[build_date] [datetime] NULL,
	[decommision_date] [datetime] NULL,
	[line_of_business] [nvarchar](50) NULL,
	[autogrow] [bit] NULL,
	[autogrow_growth] [int] NULL,
	[autogrow_growth_tpye] [nvarchar](10) NULL,
	[autogrow_max_size] [bigint] NULL,
	[date_time_added] [datetime] NULL,
 CONSTRAINT [pk_ID_dbID] PRIMARY KEY CLUSTERED 
(
	[dbID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DBAWORK].[dbo].[tb_Stored_Procedure_Execution_Daily_Chk]') AND TYPE IN (N'U'))
CREATE TABLE [DBAWORK].[dbo].[tb_Stored_Procedure_Execution_Daily_Chk](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DB_Name] [nvarchar](250) NULL,
	[SP_Name] [sysname] NOT NULL,
	[last_elapsed_time] [bigint] NULL,
	[Date] [datetime] NOT NULL,
 CONSTRAINT [pk_ID_SPDlyChk] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DBAWORK].[dbo].[tb_Stored_Procedure_Execution_Daily_Chk_Prob]') AND TYPE IN (N'U'))
CREATE TABLE [DBAWORK].[dbo].[tb_Stored_Procedure_Execution_Daily_Chk_Prob](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[SP_Name] [sysname] NOT NULL,
 CONSTRAINT [pk_ID_SPDlyChkProb] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_PacketActivity]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_PacketActivity](
	[PacketsReceivedBase] [bigint] NULL,	
	[PacketsSentBase] [bigint] NULL,
	[PacketErrorsBase] [bigint] NULL,
	[Date] [datetime] NOT NULL,
	[seconds] [int] NULL,
	[PacketsReceived] [int] NULL,	
	[PacketsSent] [int] NULL,
	[PacketErrors] [int] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_PacketErrors] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_cpu_history]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_cpu_history](
	[Date] [datetime] NULL,
	[SQLProcessUtilization] [int] NULL,
	[SystemIdle] [int] NULL,
	[OtherProcessUtilization] [int] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_CPU] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_SQLProcessUtilization' AND object_id = OBJECT_ID('tb_cpu_history'))
CREATE NONCLUSTERED INDEX [idx_SQLProcessUtilization] ON [dbo].[tb_cpu_history]
(	[SQLProcessUtilization] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_batchrequests_history]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_batchrequests_history](
	[object_name] [nchar](128) NOT NULL,
	[counter_name] [nchar](128) NOT NULL,
	[cntr_value] [bigint] NOT NULL,
	[Date] [datetime] NOT NULL,
	[seconds] [int] NOT NULL,
	[requests] [bigint] NOT NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_seconds' AND object_id = OBJECT_ID('tb_batchrequests_history'))
CREATE NONCLUSTERED INDEX [idx_seconds] ON [dbo].[tb_batchrequests_history]
(	[seconds] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Memory_History]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Memory_History](
	[Total_Physical_Memory_KB] [bigint] NULL,
	[Total_Physical_Memory_KB_Available] [bigint] NULL,
	[Total_Virtual_Memory_KB] [bigint] NULL,
	[Total_Virtual_Memory_KB_Available] [bigint] NULL,
	[Total_Page_File_Memory_KB] [bigint] NULL,
	[Total_Page_File_Memory_KB_Available] [bigint] NULL,
	[Total_System_Cache_Memory_KB_Available] [bigint] NULL,
	[Mem_Needed_KB_Per_Current_Workload] [bigint] NULL,
	[Mem_Used_KB_Maintaining_Connections] [bigint] NULL,
	[Mem_Used_KB_Locks] [bigint] NULL,
	[Mem_Used_KB_Dynamic_Cache] [bigint] NULL,
	[Mem_Used_KB_Query_Optimization] [bigint] NULL,
	[Mem_Used_KB_Hash_Sort_Index_Operations] [bigint] NULL,
	[Mem_Used_KB_Cursors] [bigint] NULL,
	[Mem_Used_KB_SQLServer] [bigint] NULL,
	[Locked_Pages_Used_SQLServer_KB] [bigint] NULL,
	[Total_VAS_KB] [bigint] NULL,
	[Memory_Grants_Pending] [bigint] NULL,
	[System_High_Memory_Signal_State] [bit] NULL,
	[System_Low_Memory_Signal_State] [bit] NULL,
	[Process_Physical_Memory_Low] [bit] NULL,
	[Process_Virtual_Memory_Low] [bit] NULL,
	[Free_List_Stalls_Per_Sec] [bigint] NULL,
	[Checkpoint_Pages_Per_Sec] [bigint] NULL,
	[Lazy_Writes_Per_Sec] [bigint] NULL,
	[Date] [datetime] NOT NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_Memory] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_Page_Life_Expectancy]') AND TYPE IN (N'U'))
CREATE TABLE [dbo].[tb_Page_Life_Expectancy](
	[Page_Life_Expectancy] [int] NULL,
	[Date] [datetime] NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [pk_ID_PageLife] PRIMARY KEY CLUSTERED 
(	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]


--View creations
If object_ID('vw_Jobs_hx')  is not null
	Drop VIEW vw_Jobs_hx
GO
CREATE VIEW [dbo].[vw_Jobs_hx]
AS
SELECT        JobName, RunStatus, CAST(DATEPART(yyyy, RunDateTime) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, RunDateTime) AS varchar(2)), 2) AS [YearWeek], COUNT(JobName) AS TotalExecutionCount, SUM(JobDurationSeconds) 
                         AS TotalElapsedTimeSeconds, SUM(JobDurationSeconds) / COUNT(JobName) AS AvgElapsedTimeSeconds, owner, NULL AS 'ServerName'
FROM            dbo.tb_Jobs_hx
WHERE        (JobFailStep = 0)
GROUP BY JobName, RunStatus, CAST(DATEPART(yyyy, RunDateTime) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, RunDateTime) AS varchar(2)), 2), owner
GO

If object_ID('vw_Indexes_W_Scans')  is not null
	Drop VIEW vw_Indexes_W_Scans
GO
CREATE VIEW [dbo].[vw_Indexes_W_Scans]
AS
SELECT        TOP (1000) H.DB_Name as DBName, H.Table_Name as TableName, H.Index_Name as IndexName, T.[RowCount], H.user_seeks, H.user_scans, H.user_lookups, H.user_updates, H.type_desc, H.fill_factor, H.is_primary_key, H.Date
FROM            dbo.tb_Index_Usage_History AS H INNER JOIN
                         dbo.tb_Table_Rows AS T ON T.DatabaseName = H.DB_Name AND T.TableName = H.Table_Name
WHERE        (H.user_scans > 100) AND (H.Index_Name IS NOT NULL) AND (H.Date > GETDATE() - 8) AND (T.Date > GETDATE() - 8)
ORDER BY H.user_scans DESC
GO

If object_ID('vw_Most_Used_Table_W_Statistics')  is not null
	Drop VIEW vw_Most_Used_Table_W_Statistics
GO
CREATE VIEW [dbo].[vw_Most_Used_Table_W_Statistics]
AS
SELECT        U.DatabaseName as DBName, U.TableName, R.[RowCount], S.Index_Name as IndexName, S.LastUpdateDate, S.rowmodctr, U.TotalAccesses, U.TotalReads, U.ReadScans, U.Date
FROM            dbo.tb_Most_Used_Table_History AS U LEFT OUTER JOIN
                         dbo.tb_Table_Rows AS R ON U.DatabaseName = R.DatabaseName AND U.TableName = R.TableName LEFT OUTER JOIN
                         dbo.tb_Statistics_History AS S ON U.DatabaseName = S.DB_Name AND U.TableName = S.Table_Name
WHERE        (U.Date > GETDATE() - 6.9) AND (R.Date > GETDATE() - 6.9) AND (S.Date > GETDATE() - 6.9)
GO

If object_ID('vw_Most_Used_Table_W_Row_Count')  is not null
	Drop VIEW vw_Most_Used_Table_W_Row_Count
GO
CREATE VIEW [dbo].[vw_Most_Used_Table_W_Row_Count]
AS
SELECT        U.DatabaseName as DBName, U.TableName, R.[RowCount], U.TotalAccesses, U.TotalReads, U.ReadScans, U.Date
FROM            dbo.tb_Most_Used_Table_History AS U LEFT OUTER JOIN
                         dbo.tb_Table_Rows AS R ON U.DatabaseName = R.DatabaseName AND U.TableName = R.TableName
WHERE        (U.Date > GETDATE() - 6.9) AND (R.Date > GETDATE() - 6.9)
GO

If object_ID('vw_Out_Of_Date_Statistics_Top_Tables')  is not null
	Drop VIEW vw_Out_Of_Date_Statistics_Top_Tables
GO
CREATE VIEW [dbo].[vw_Out_Of_Date_Statistics_Top_Tables]
AS
SELECT        TOP (1000) DBName, TableName, [RowCount], IndexName, LastUpdateDate, rowmodctr, TotalAccesses, TotalReads, ReadScans, Date,'UPDATE STATISTICS ' + TableName + '(' + IndexName + ') WITH FULLscan' AS RebuildState
FROM            dbo.vw_Most_Used_Table_W_Statistics
WHERE        (IndexName IS NOT NULL) AND ([RowCount] > 100000) AND (TotalAccesses > 100000) AND (rowmodctr > 100000) AND (LastUpdateDate < GETDATE() - 7)
ORDER BY [RowCount]
GO

If object_ID('vw_Top_Used_Tables_Fragmented')  is not null
	Drop VIEW vw_Top_Used_Tables_Fragmented
GO
CREATE VIEW [dbo].[vw_Top_Used_Tables_Fragmented]
AS
SELECT        F.DB_Name as DBName, F.Table_Name as TableName, F.Index_Name as IndexName, F.Avg_Fragmentation, F.Date, F.page_count, H_1.TotalAccesses, H_1.TotalReads, H_1.ReadScans,
			   'ALTER INDEX [' + F.Index_Name + '] ON [dbo].[' + F.Table_Name + '] REBUILD with (ONLINE = ON)' AS Rebuild
FROM            dbo.tb_Fragmentation_History AS F INNER JOIN
                             (SELECT        TOP (100) DatabaseName, TableName, TotalAccesses, TotalWrites, PercentAccessesAreWrites, TotalReads, PercentAccessesAreReads, ReadSeeks, PercentReadsAreIndexSeeks, ReadScans, 
                                                         PercentReadsAreIndexScans, Date
                               FROM            dbo.tb_Most_Used_Table_History AS H
                               WHERE        (Date > GETDATE() - 6.9)) AS H_1 ON H_1.DatabaseName = F.DB_Name AND H_1.TableName = F.Table_Name
WHERE        (F.Date > GETDATE() - 6.9) AND (F.Avg_Fragmentation > 30) and page_count > 8
GO

If object_ID('vw_Indexes_W_Free_Space_To_Rebuild')  is not null
	Drop VIEW vw_Indexes_W_Free_Space_To_Rebuild
GO
CREATE VIEW [dbo].[vw_Indexes_W_Free_Space_To_Rebuild]
AS
SELECT        I.DB_Name as DBName, I.Table_Name as TableName, I.Index_ID as IndexID, I.Index_Name as IndexName, I.Type, I.Total_MBs, I.Free_Space_MBs, I.Free_Space_Percent, T.[RowCount] AS 'TableRowCount', T.TotalAccesses, I.Date,
			   'ALTER INDEX [' + I.Index_Name + '] ON [dbo].[' + I.Table_Name + '] REBUILD with (ONLINE = ON)' AS Rebuild
FROM            dbo.tb_Index_Free_Space AS I LEFT OUTER JOIN
                         dbo.vw_Most_Used_Table_W_Row_Count AS T ON I.DB_Name = T.DBName AND I.Table_Name = T.TableName
WHERE        (I.Date > GETDATE() - 6.9) AND (I.Free_Space_MBs > 50) OR (I.Free_Space_Percent > 50)
GO

If object_ID('vw_SP_Execution_Time_Count')  is not null
	Drop VIEW vw_SP_Execution_Time_Count
GO
CREATE VIEW [dbo].[vw_SP_Execution_Time_Count]
AS
SELECT        DB_Name AS DBName, [SP Name] AS SPName, cached_time, SUM(execution_count) AS TotalExecutionCount, SUM(total_elapsed_time) AS TotalElapsedTime, SUM(total_elapsed_time) / SUM(execution_count) 
                         / 1000 AS AvgExecutionDurationMilliSeconds, CASE WHEN (SUM(total_elapsed_time) / SUM(execution_count)) < 1000000 THEN '1 Sec' WHEN (SUM(total_elapsed_time) / SUM(execution_count)) 
                         < 5000000 THEN '5 Sec' WHEN (SUM(total_elapsed_time) / SUM(execution_count)) < 30000000 THEN '30 Sec' ELSE '> 30 Sec' END AS ExecTimeCat, SUM(TotalLogicalReads) / SUM(execution_count) 
                         AS AvgLogicalReads, SUM(TotalLogicalWrites) / SUM(execution_count) AS AvgTotalLogicalWrites, CAST(DATEPART(yyyy, Date) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, Date) AS varchar(2)), 2) AS [YearWeek], 
                         CASE WHEN (SUM(total_elapsed_time) / SUM(execution_count)) < 1000000 THEN 1 WHEN (SUM(total_elapsed_time) / SUM(execution_count)) < 5000000 THEN 2 WHEN (SUM(total_elapsed_time) 
                         / SUM(execution_count)) < 30000000 THEN 3 ELSE 4 END AS SortOrder
FROM            dbo.tb_Stored_Procedure_Execution_History
GROUP BY DB_Name, [SP Name], cached_time, CAST(DATEPART(yyyy, Date) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, Date) AS varchar(2)), 2)
GO

If object_ID('vw_Batch_Volumes')  is not null
	Drop VIEW vw_Batch_Volumes
GO
CREATE VIEW [dbo].[vw_Batch_Volumes]
AS
SELECT        DATEPART(dw, Date) AS DayOfWeekday, DATENAME(dw, Date) AS Weekday, DATEPART(hh, Date) AS Hour, DATEPART(mm, Date) AS Month, SUM(requests) / SUM(seconds) AS 'RequestsPerSecond', COUNT(Date) 
                         AS 'MeasureCount', CAST(CAST(DATEPART(YYYY, Date) AS varchar(4)) + RIGHT('0' + CAST(DATEPART(mm, Date) AS varchar(2)), 2) + RIGHT('0' + CAST(DATEPART(d, Date) AS varchar(2)), 2) AS int) AS DateKey,
	                    CAST(DATEPART(yyyy, Date) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, Date) AS varchar(2)), 2) AS YearWeek
FROM            dbo.tb_batchrequests_history
WHERE        (seconds > 0)
GROUP BY counter_name, DATENAME(dw, Date), DATEPART(hh, Date), DATEPART(mm, Date), DATEPART(dw, Date), CAST(CAST(DATEPART(YYYY, Date) AS varchar(4)) + RIGHT('0' + CAST(DATEPART(mm, Date) AS varchar(2)),
                          2) + RIGHT('0' + CAST(DATEPART(d, Date) AS varchar(2)), 2) AS int),CAST(DATEPART(yyyy, Date) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, Date) AS varchar(2)), 2)
GO

If object_ID('vw_Unneeded_Indexes')  is not null
	Drop VIEW vw_Unneeded_Indexes
GO
CREATE VIEW [dbo].[vw_Unneeded_Indexes]
AS
SELECT        DB_Name AS DBName, Table_Name AS TableName, Index_Name AS IndexName, SUM(user_seeks) AS TotalSeeks, SUM(user_scans) AS TotalScans, SUM(user_lookups) AS TotalLookups, 
cast(avg(user_updates) as INT) AS AvgWeekUpdates, MIN(FirstDate) AS FirstDate, MAX(LastDate) AS LastDate
FROM           
 (SELECT        DB_Name, Table_Name, Index_Name, user_seeks, user_scans, user_lookups, user_updates, MIN(Date) AS FirstDate, MAX(Date) AS LastDate
                          FROM            dbo.tb_Index_Usage_History
                          GROUP BY DB_Name, Table_Name, Index_Name, user_seeks, user_scans, user_lookups, user_updates, is_primary_key, type_desc
                          HAVING          (Index_Name IS NOT NULL) AND (is_primary_key = 0) 
						  AND (type_desc = 'NONCLUSTERED') AND (DB_Name NOT IN ('tempdb'))
						  ) AS A
GROUP BY DB_Name, Table_Name, Index_Name
having sum(user_scans) = 0 and sum(user_seeks) = 0 and sum(user_lookups) = 0
and        (MAX(LastDate) > GETDATE() - 6.9)
GO

If object_ID('vw_Performance_History_BI')  is not null
	Drop VIEW vw_Performance_History_BI
GO
CREATE VIEW [dbo].vw_Performance_History_BI
AS
SELECT        TOP (100) PERCENT D.server_name AS ServerName, D.database_name AS DatabaseName, P.database_drive AS DatabaseDrive, P.database_file_name AS FileName, P.TotalIO, P.TotalMBs, P.IoStallMS, 
                         P.AvgStallPerIO, P.report_date_time_end, CAST(CAST(DATEPART(YYYY, P.report_date_time_end) AS varchar(4)) + RIGHT('0' + CAST(DATEPART(mm, P.report_date_time_end) AS varchar(2)), 2) 
                         + RIGHT('0' + CAST(DATEPART(d, P.report_date_time_end) AS varchar(2)), 2) AS int) AS DateKey, DATEPART(hh, P.report_date_time_end) AS Hour, DATEDIFF(mi, P.report_date_time_start, P.report_date_time_end) 
                         AS MinutesElapsed, CAST(DATEPART(yyyy, P.report_date_time_end) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, P.report_date_time_end) AS varchar(2)), 2) AS YearWeek
FROM            dbo.tb_monitor_sql_database_performance_hx AS P INNER JOIN
                         dbo.tb_Servers_Databases AS D ON P.dbID = D.dbID AND P.serID = D.serID
GO

If object_ID('vw_Jobs_Detail_hx')  is not null
	Drop VIEW vw_Jobs_Detail_hx
GO
CREATE VIEW [dbo].[vw_Jobs_Detail_hx]
AS
SELECT        JobName, RunDateTime, CAST(DATEPART(yyyy, RunDateTime) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, RunDateTime) AS varchar(2)), 2) AS [YearWeek], JobDurationSeconds, RunStatus, owner, source, 
                         Date
FROM            dbo.tb_Jobs_hx
WHERE        (JobFailStep = 0)
GO

If object_ID('vw_SP_Execution_Time_Detail')  is not null
	Drop VIEW vw_SP_Execution_Time_Detail
GO
CREATE VIEW [dbo].[vw_SP_Execution_Time_Detail]
AS
SELECT        DB_Name AS DBName, [SP Name] AS SPName, Date, execution_count AS TotalExecutionCount, total_elapsed_time AS TotalElapsedTime, CASE WHEN ((total_elapsed_time) / (execution_count)) 
                         < 1000000 THEN '1 Sec' WHEN ((total_elapsed_time) / (execution_count)) < 5000000 THEN '5 Sec' WHEN ((total_elapsed_time) / (execution_count)) 
                         < 30000000 THEN '30 Sec' ELSE '> 30 Sec' END AS ExecTimeCat, TotalLogicalReads, TotalLogicalWrites, CAST(DATEPART(yyyy, Date) AS varchar(4)) + '.' + RIGHT ('0' + CAST(DATEPART(ww, Date) AS varchar(2)), 2) 
                         AS YearWeek, total_elapsed_time / execution_count AS AvgExecutionDurationMilliSeconds, CASE WHEN ((total_elapsed_time) / (execution_count)) < 1000000 THEN 1 WHEN ((total_elapsed_time) 
                         / (execution_count)) < 5000000 THEN 2 WHEN ((total_elapsed_time) / (execution_count)) < 30000000 THEN 3 ELSE 4 END AS SortOrder
FROM            dbo.tb_Stored_Procedure_Execution_History
GROUP BY DB_Name, [SP Name], Date, TotalLogicalReads, TotalLogicalWrites, execution_count, total_elapsed_time
GO

If object_ID('vw_Table_Row_Counts')  is not null
	Drop VIEW vw_Table_Row_Counts
GO
CREATE VIEW [dbo].[vw_Table_Row_Counts]
AS
SELECT        DatabaseName, TableNameFull, TableName, [RowCount], Date
FROM            dbo.tb_Table_Rows
WHERE        (Date > GETDATE() - 6.9) AND (DatabaseName <> 'tempdb')
GO

If object_ID('vw_Table_Row_Trend')  is not null
	Drop VIEW vw_Table_Row_Trend
GO
CREATE VIEW [dbo].[vw_Table_Row_Trend]
AS
SELECT        DatabaseName, TableName, [RowCount], Date
FROM            dbo.tb_Table_Rows
WHERE        (DatabaseName <> 'tempdb')
GO

If object_ID('vw_AnalysisUpperLowerBoundsSP')  is not null
	Drop VIEW vw_AnalysisUpperLowerBoundsSP
GO
CREATE VIEW [dbo].[vw_AnalysisUpperLowerBoundsSP]
AS
SELECT        DB_Name, [SP Name], AVG(avg_elapsed_time) AS Mean, STDEVP(avg_elapsed_time) AS StandardDev, AVG(avg_elapsed_time) - 3 * STDEVP(avg_elapsed_time) AS LowerBound, AVG(avg_elapsed_time) 
                         + 3 * STDEVP(avg_elapsed_time) AS UpperBound, COUNT(*) AS SampleSize
FROM            dbo.tb_Stored_Procedure_Execution_History
GROUP BY DB_Name, [SP Name]
HAVING        (COUNT(*) > 1)
GO

If object_ID('vw_AnalysisUpperLowerBoundsSvr')  is not null
	Drop VIEW vw_AnalysisUpperLowerBoundsSvr
GO
CREATE VIEW [dbo].[vw_AnalysisUpperLowerBoundsSvr]
AS
SELECT        JobName, JobFailStep, AVG(JobDurationSeconds) AS Mean, STDEVP(JobDurationSeconds) AS StandardDev, AVG(JobDurationSeconds) - 3 * STDEVP(JobDurationSeconds) AS LowerBound, 
                         AVG(JobDurationSeconds) + 3 * STDEVP(JobDurationSeconds) AS UpperBound, RunStatus, COUNT(*) AS SampleSize, source
FROM            dbo.tb_Jobs_hx
GROUP BY JobName, JobFailStep, RunStatus, source
HAVING        (COUNT(*) > 1)
GO

If object_ID('vw_AnalysisJobExecutionOutsideOfRangeSvr')  is not null
	Drop VIEW vw_AnalysisJobExecutionOutsideOfRangeSvr
GO
CREATE VIEW [dbo].[vw_AnalysisJobExecutionOutsideOfRangeSvr]
AS
SELECT        H.JobName, H.JobFailStep, H.JobDurationSeconds, H.RunDateTime, S.Mean, S.StandardDev, S.LowerBound, S.UpperBound, H.RunStatus, S.SampleSize, CAST(H.RunDateTime AS Date) AS DateOnly, 
                         DATEPART(hh, H.RunDateTime) AS Hour, S.source
FROM            dbo.vw_AnalysisUpperLowerBoundsSvr AS S INNER JOIN
                             (SELECT        JobName, JobFailStep, JobFailMessage, RunDateTime, JobDurationSeconds, RunStatus, source
                               FROM            dbo.tb_Jobs_hx
                               WHERE        (JobDurationSeconds > 3) AND (RunDateTime > GETDATE() - 35)) AS H ON H.JobName = S.JobName AND H.JobFailStep = S.JobFailStep AND H.RunStatus = S.RunStatus AND 
                         H.source = S.source
WHERE        (H.JobDurationSeconds NOT BETWEEN S.LowerBound AND S.UpperBound)
GO

If object_ID('vw_AnalysisSPExecutionOutsideOfRangeSvr')  is not null
	Drop VIEW vw_AnalysisSPExecutionOutsideOfRangeSvr
GO
CREATE VIEW [dbo].[vw_AnalysisSPExecutionOutsideOfRangeSvr]
AS
SELECT        H.DB_Name, H.[SP Name], H.avg_elapsed_time, H.Date, S.Mean, S.StandardDev, S.LowerBound, S.UpperBound, S.SampleSize, CAST(H.Date AS Date) AS DateOnly
FROM            dbo.vw_AnalysisUpperLowerBoundsSP AS S INNER JOIN
                             (SELECT        DB_Name, [SP Name], Date, avg_elapsed_time
                               FROM            dbo.tb_Stored_Procedure_Execution_History
                               WHERE        (avg_elapsed_time > 3) AND (Date > GETDATE() - 35)) AS H ON H.DB_Name = S.DB_Name AND H.[SP Name] = S.[SP Name]
WHERE        (H.avg_elapsed_time NOT BETWEEN S.LowerBound AND S.UpperBound)
GO

If object_ID('vw_AnalysisSPExecutionOutsideOfRangeSummarySvr')  is not null
	Drop VIEW vw_AnalysisSPExecutionOutsideOfRangeSummarySvr
GO
CREATE VIEW [dbo].[vw_AnalysisSPExecutionOutsideOfRangeSummarySvr]
AS
SELECT        DB_Name, [SP Name], COUNT([SP Name]) AS Counts, AVG(avg_elapsed_time) AS AvgElapsedTime, Mean, StandardDev, LowerBound, UpperBound, SampleSize, MAX(DateOnly) AS MostRecentDateOnly
FROM            dbo.vw_AnalysisSPExecutionOutsideOfRangeSvr
GROUP BY DB_Name, [SP Name], Mean, StandardDev, LowerBound, UpperBound, SampleSize
GO

If object_ID('vw_AnalysisJobExecutionOutsideOfRangeSummarySvr')  is not null
	Drop VIEW vw_AnalysisJobExecutionOutsideOfRangeSummarySvr
GO
CREATE VIEW [dbo].[vw_AnalysisJobExecutionOutsideOfRangeSummarySvr]
AS
SELECT        JobName, JobFailStep, COUNT(JobName) AS Counts, AVG(JobDurationSeconds) AS AvgJobDurationSeconds, Mean, StandardDev, LowerBound, UpperBound, RunStatus, SampleSize, MAX(DateOnly) 
                         AS MostRecentDateOnly, Hour, source
FROM            dbo.vw_AnalysisJobExecutionOutsideOfRangeSvr
GROUP BY JobName, JobFailStep, Mean, StandardDev, LowerBound, UpperBound, RunStatus, SampleSize, Hour, source
GO

If object_ID('vw_Tables_w_No_Changes')  is not null
	Drop VIEW vw_Tables_w_No_Changes
GO
CREATE VIEW [dbo].[vw_Tables_w_No_Changes]
AS
WITH TableCounts([DatabaseName], [TableNameFull], [TableName], [RowCount]) AS (SELECT DISTINCT DatabaseName, TableNameFull, TableName, [RowCount]
                                                                                               FROM            dbo.tb_Table_Rows
                                                                                               WHERE        (DatabaseName NOT IN ('tempdb')))
    SELECT        [DatabaseName], [TableName]
     FROM            TableCounts AS TableCounts_1
     GROUP BY [DatabaseName], [TableNameFull], [TableName]
     HAVING         (COUNT([RowCount]) = 1)
GO

If object_ID('vw_PerformanceHistory')  is not null
	Drop VIEW vw_PerformanceHistory
GO
CREATE VIEW [dbo].[vw_PerformanceHistory]
AS
SELECT        TOP (100) PERCENT D.server_name, D.database_name, P.database_drive, P.database_file_name, P.NumberReads, P.NumberWrites, P.TotalIO, CASE DATEDIFF(d, P.report_date_time_start, 
                         P.report_date_time_end) WHEN 0 THEN 0 ELSE P.[TotalIO] / (CASE DATEDIFF(d, P.report_date_time_start, P.report_date_time_end) WHEN 0 THEN 1 ELSE DATEDIFF(d, P.report_date_time_start, 
                         P.report_date_time_end) END) END AS TotalIOperDay, P.MBsRead, P.MBsWritten, P.TotalMBs, CASE DATEDIFF(d, P.report_date_time_start, P.report_date_time_end) 
                         WHEN 0 THEN 0 ELSE P.[TotalMBs] / (CASE DATEDIFF(d, P.report_date_time_start, P.report_date_time_end) WHEN 0 THEN 1 ELSE DATEDIFF(d, P.report_date_time_start, P.report_date_time_end) END) 
                         END AS TotalMBsperDay, P.IoStallReadMS, P.IoStallWriteMS, P.IoStallMS, P.AvgStallPerReadIO, P.AvgStallPerWriteIO, P.AvgStallPerIO, P.report_date_time_start, P.report_date_time_end, 
                         CAST(CONVERT(varchar(8), P.report_date_time_end, 112) AS datetime) AS End_Date, DATEDIFF(d, P.report_date_time_start, P.report_date_time_end) AS Days
FROM            dbo.tb_monitor_sql_database_performance_hx AS P INNER JOIN
                         dbo.tb_Servers_Databases AS D ON P.dbID = D.dbID AND P.serID = D.serID
GO

If object_ID('vw_Unused_Tables')  is not null
	Drop VIEW vw_Unused_Tables
GO
CREATE VIEW [dbo].[vw_Unused_Tables]
AS
SELECT        TOP (100) PERCENT T.DatabaseName, T.TableName, SUM(H.TotalAccesses) AS TotalAccesses, SUM(T.[RowCount]) AS [RowCount]
FROM            dbo.vw_Table_Row_Counts AS T LEFT OUTER JOIN
                         dbo.tb_Most_Used_Table_History AS H ON T.DatabaseName = H.DatabaseName AND T.TableName = H.TableName
GROUP BY T.DatabaseName, T.TableName
HAVING        (T.DatabaseName <> 'tempdb')
GO


--add table compression
USE DBAWORK
GO

ALTER TABLE dbo.tb_Statistics_History REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE)

ALTER TABLE dbo.tb_Stored_Procedure_History REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE)

ALTER TABLE dbo.tb_cpu_history REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE)

ALTER TABLE dbo.tb_Jobs_hx REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE)

ALTER TABLE dbo.tb_monitor_sql_database_performance_hx REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE)

ALTER TABLE dbo.tb_Fragmentation_History REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE)

ALTER TABLE dbo.tb_lock_history REBUILD PARTITION = ALL
WITH (DATA_COMPRESSION = PAGE, MAXDOP = 4, online=on)


--default parameters
IF NOT EXISTS (SELECT * FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_io_performance' and Class='Days')
INSERT INTO DBAWORK.[dbo].[tb_Parameters] ([Item],[SP_Name],[Class],[Date])
     VALUES ('180','bp_io_performance','Days',getdate())
GO

IF NOT EXISTS (SELECT * FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_long_run_SP' and Class='Minutes')
INSERT INTO DBAWORK.[dbo].[tb_Parameters] ([Item],[SP_Name],[Class],[Date])
     VALUES ('120','bp_long_run_SP','Minutes',getdate())
GO

IF NOT EXISTS (SELECT * FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_long_run_SP' and Class='Exclusion')
INSERT INTO DBAWORK.[dbo].[tb_Parameters] ([Item],[SP_Name],[Class],[Date])
     VALUES ('bp_long_run_SP','bp_long_run_SP','Exclusion',getdate())
GO

IF NOT EXISTS (SELECT * FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='ALL' and Class='DBA Email')
INSERT INTO DBAWORK.[dbo].[tb_Parameters] ([Item],[SP_Name],[Class],[Date])
     VALUES ('DL-DataServices@silverstarbrands.com','ALL','DBA Email',getdate())
GO

IF NOT EXISTS (SELECT * FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_index_frag_history' and Class='Days')
INSERT INTO DBAWORK.[dbo].[tb_Parameters] ([Item],[SP_Name],[Class],[Date])
     VALUES ('180','bp_index_frag_history','Days',getdate())
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create proc [dbo].[bp_index_frag_history] as

--exec DBAWORK..bp_index_frag_history

--built by Todd Palecek 9/17/14 to track history of index fragmentation
--indexes with less than 8 pages are not rebuilt by maintenance plans (http://www.sqlservercentral.com/Forums/Topic1504105-391-1.aspx)
--rebuild of indexes also updates stats; but not column stats (http://www.sqlskills.com/blogs/paul/search-engine-qa-10-rebuilding-indexes-and-updating-statistics/)
--return history for analysis; less than 8 pages no rebuild per SQL rules; ola defrags at above 1000 pages per a whitepaper based on sql 2000

--set days of history to keep
DECLARE @dayshistory	INT,
		@servername		nvarchar(100)

set @dayshistory = cast((select Item FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_index_frag_history' and Class='Days') as INT)
set @servername = (select @@servername)

update [DBAWORK].[dbo].[tb_Servers]
set    [sql_version_num] =convert(nvarchar(25),SERVERPROPERTY('ProductVersion'))
      ,[sql_edition]= convert(nvarchar(33),SERVERPROPERTY('Edition') )

update [DBAWORK].[dbo].[tb_Servers]
set    [sql_physical_cpus] = (SELECT  cpu_count FROM    sys.dm_os_sys_info)
      ,[sql_logical_cpus] = (SELECT  cpu_count / hyperthread_ratio FROM    sys.dm_os_sys_info)

update [DBAWORK].[dbo].[tb_Servers]
	  set AvailableRAM = (select total_physical_memory_kb/1024  from sys.dm_os_sys_memory)
	
update [DBAWORK].[dbo].[tb_Servers]
	  set MaxSQLRAM = (SELECT  cntr_value/1024 FROM sys.dm_os_performance_counters WHERE counter_name = 'Total Server Memory (KB)')

update [DBAWORK].[dbo].[tb_Servers]
	  set windows_version_num = (select substring(RIGHT(@@version, LEN(@@version)- 3 -charindex (' ON ', @@VERSION)),11,4))


 IF OBJECT_ID('tempdb..#TempMostUsedTbl') IS NOT NULL
 DROP TABLE #TempMostUsedTbl
 
CREATE TABLE #TempMostUsedTbl
 (DatabaseName NVARCHAR(500), TableName NVARCHAR(500), UserSeeks DEC, UserScans DEC, UserUpdates DEC)
 
 
--table fragmentation
if @servername not in ('DAXDBS04','DAX-REPLDB01', 'dc1-dwdb1','dc1-stgdaxdb01','dc1-daxdevdb01','dax-scrubdb01','dc1-stgdwdb1','dc1-intdwdb1') --servers too large the index eval times out
BEGIN
begin try
exec sp_MSforeachdb 'Use ?; insert into DBAWORK..tb_Fragmentation_History SELECT db_name(ps.database_id) as DB_Name, object_name(ps.OBJECT_ID) as Table_Name,
 ps.index_id, b.name, ps.avg_fragmentation_in_percent, getdate(), page_count, partition_number
 FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS ps
 INNER JOIN sys.indexes AS b ON ps.OBJECT_ID = b.OBJECT_ID AND ps.index_id = b.index_id
 WHERE ps.database_id = DB_ID()'
 --2000 does not exist sys.dm_db_index_physical_stats 
  end try
 begin catch
 end catch
END
--else
--BEGIN
--add to only take top tables
--END


 --statistics history
 begin try
 exec sp_MSforeachdb 'Use ?; insert into DBAWORK..tb_Statistics_History SELECT (SELECT DB_NAME()) as Database_Name, OBJECT_NAME(id) as Table_Name,name as Index_Name,
 STATS_DATE(id, indid) LastUpdateDate ,rowmodctr, getdate()
 FROM sys.sysindexes'
  end try
 begin catch
 end catch

 --2000
 /*
 SELECT (SELECT DB_NAME()) as Database_Name, OBJECT_NAME(id) as Table_Name,name as Index_Name,
 STATS_DATE(id, indid) LastUpdateDate ,rowmodctr, getdate()
 FROM sysindexes
 order by rowmodctr DESC, LastUpdateDate
 */

--update most used tables
 --for sp_foreachdb may not work but will not throw an error, doesn't like nested insert, with sp_MSforeachdb, may fail on the databases with poor name only
begin try
 INSERT INTO #TempMostUsedTbl
 EXEC sp_MSforeachdb 'USE [?]; IF DB_ID(''?'') > 4
 BEGIN
 SELECT DB_NAME(), object_name(b.object_id), a.user_seeks, a.user_scans, a.user_updates 
 FROM sys.dm_db_index_usage_stats a
 RIGHT OUTER JOIN [?].sys.indexes b on a.object_id = b.object_id and a.database_id = DB_ID()
 WHERE b.object_id > 100 
 END'
 end try
 begin catch
 end catch
  
 --2000 does not exist sys.dm_db_index_physical_stats 

 insert into DBAWORK.dbo.tb_Most_Used_Table_History
 SELECT DatabaseName, TableName as 'Table Name', sum(UserSeeks + UserScans + UserUpdates) as 'Total Accesses',
 sum(UserUpdates) as 'Total Writes', 
 CONVERT(DEC(25,2),(sum(UserUpdates)/sum(UserSeeks + UserScans + UserUpdates)*100)) as '% Accesses are Writes',
 sum(UserSeeks + UserScans) as 'Total Reads', 
 CONVERT(DEC(25,2),(sum(UserSeeks + UserScans)/sum(UserSeeks + UserScans + UserUpdates)*100)) as '% Accesses are Reads',
 SUM(UserSeeks) as 'Read Seeks', CONVERT(DEC(25,2),(SUM(UserSeeks)/sum(UserSeeks + UserScans)*100)) as '% Reads are Index Seeks', --faster than scan
 SUM(UserScans) as 'Read Scans', CONVERT(DEC(25,2),(SUM(UserScans)/sum(UserSeeks + UserScans)*100)) as '% Reads are Index Scans',  --looks at entire index
 getdate()
 FROM #TempMostUsedTbl
 GROUP by TableName, DatabaseName
 --divide by zero error if include UserUpdates in HAVING
 HAVING sum(UserSeeks + UserScans) > 0
 ORDER by sum(UserSeeks + UserScans + UserUpdates) DESC


 --stored proc and function usage; time in microseconds 1,000,000 microseconds = 1 second; 1,000 milliseconds = 1 second
 begin try
 exec sp_MSforeachdb 'Use ?; insert into DBAWORK..tb_Stored_Procedure_History  SELECT  (SELECT DB_NAME()) as [DB_Name], O.Name as SPName 
        ,O.Create_Date, O.Modify_Date ,C.Execution_Count, getdate() as [Date]
FROM sys.objects as O  
left outer join 
(SELECT OBJECT_SCHEMA_NAME(st.objectid,dbid) SchemaName
 ,OBJECT_NAME(st.objectid,dbid) StoredProcedure, sum(cp.usecounts) Execution_Count
 FROM sys.dm_exec_cached_plans cp
 CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
 WHERE DB_NAME(st.dbid) IS NOT NULL AND cp.objtype = ''Proc''
 GROUP BY OBJECT_SCHEMA_NAME(objectid,st.dbid),
 OBJECT_NAME(objectid,st.dbid)
) C on C.StoredProcedure = O.Name
WHERE O.type in (''P'',''X'',''AF'',''FN'',''FS'',''FT'',''IF'',''PC'',''TF'')'
 end try
 begin catch
 end catch

 --stored proc execution usage
 begin try
 exec sp_MSforeachdb 'Use ?; insert into DBAWORK..tb_Stored_Procedure_Execution_History  SELECT TOP(200) (SELECT DB_NAME()) as [DB_Name], p.name AS [SP Name], qs.execution_count,
ISNULL(qs.execution_count/DATEDIFF(Second, qs.cached_time, GETDATE()), 0) AS [Calls/Second],
qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], qs.total_worker_time AS [TotalWorkerTime],  
qs.total_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time], qs.cached_time,
qs.total_logical_reads AS [TotalLogicalReads], qs.total_logical_reads/qs.execution_count AS [AvgLogicalReads],
qs.total_logical_writes AS [TotalLogicalWrites], qs.total_logical_writes/qs.execution_count AS [AvgLogicalWrites],
getdate() as [Date]
FROM sys.procedures AS p
INNER JOIN sys.dm_exec_procedure_stats AS qs
ON p.[object_id] = qs.[object_id]
WHERE qs.database_id = DB_ID()
ORDER BY qs.execution_count DESC'
--select * from sys.dm_exec_procedure_stats not in 2005
 end try
 begin catch
 end catch


 --top queries by longest avg execution time
 begin try
 insert into DBAWORK.dbo.tb_Top_Queries_History  
 SELECT TOP 25
	object_name(qt.objectid) as name, 
	db_name(qt.[dbid]) as [DB_Name], 
    qs.execution_count, qs.total_logical_reads, qs.last_logical_reads,
	qs.total_logical_writes, qs.last_logical_writes,
	qs.total_elapsed_time/1000000 total_elapsed_time_in_S,
	qs.last_elapsed_time/1000000 last_elapsed_time_in_S,
	(qs.total_elapsed_time/1000)/qs.execution_count AvgExecutionDuration1000sOfSeconds, 
	AvgPhysicalReads  = isnull( qs.total_physical_reads/ qs.execution_count, 0 ),  
	MinPhysicalReads  = qs.min_physical_reads,  
	MaxPhysicalReads  = qs.max_physical_reads,  
	AvgPhysicalReads_kbsize  = isnull( qs.total_physical_reads/ qs.execution_count, 0 ) *8,  
	MinPhysicalReads_kbsize  = qs.min_physical_reads*8,  
	MaxPhysicalReads_kbsize  = qs.max_physical_reads*8,  
	CreationDateTime = qs.creation_time,  
    qs.last_execution_time,
   SUBSTRING(qt.[text], qs.statement_start_offset/2, (   
          CASE WHEN qs.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), qt.[text])) * 2    
			       ELSE qs.statement_end_offset    
			       END - qs.statement_start_offset)/2) AS query_text,   
	tp.query_plan,  
	0 as 'missing_index_info',
	getdate() as Date
   FROM    
      sys.dm_exec_query_stats qs   
      CROSS APPLY sys.dm_exec_sql_text (qs.[sql_handle]) AS qt   
      OUTER APPLY sys.dm_exec_query_plan(qs.plan_handle) tp   
	   ORDER BY  (qs.total_elapsed_time/1000)/qs.execution_count DESC
 end try
 begin catch
 end catch


 --index usage history
 begin try
 exec sp_MSforeachdb 'Use ?; insert into DBAWORK..tb_Index_Usage_History
 select db_name(S.database_id) as [DB_Name], object_name(S.object_id) as Table_Name, I.name as Index_Name, S.user_seeks, S.user_scans, S.user_lookups, S.user_updates,
 S.last_user_seek, S.last_user_scan, S.last_user_lookup, S.last_user_update, I.type_desc, I.fill_factor, I.is_primary_key, getdate() as [Date]
 from sys.dm_db_index_usage_stats S
 inner join sys.indexes I on I.object_id = S.object_id and I.index_id = S.index_id
 order by  object_name(S.object_id)'
  end try
 begin catch
 end catch


--index free space
begin Try
EXEC sp_MSforeachdb
    N'IF EXISTS (SELECT 1 FROM (SELECT DISTINCT DB_NAME ([database_id]) AS [name]
    FROM sys.dm_os_buffer_descriptors) AS names WHERE [name] = ''?'')
BEGIN
USE [?]; insert into DBAWORK..tb_Index_Free_Space
SELECT ''?'' AS [DB_Name],
    OBJECT_NAME (p.[object_id]) AS [Table_Name],
    p.[index_id],
    i.[name] AS [Index_Name],
    i.[type_desc] AS [Type],
    (DPCount + CPCount) * 8 / 1024 AS [TotalMB],
    ([DPFreeSpace] + [CPFreeSpace]) / 1024 / 1024 AS [FreeSpaceMB],
    CAST (ROUND (100.0 * (([DPFreeSpace] + [CPFreeSpace]) / 1024) / (([DPCount] + [CPCount]) * 8), 1) AS DECIMAL (4, 1)) AS [FreeSpacePC],
	getdate() as [Date]
FROM
    (SELECT allocation_unit_id,
        SUM (CASE WHEN ([is_modified] = 1) THEN 1 ELSE 0 END) AS [DPCount],
        SUM (CASE WHEN ([is_modified] = 1) THEN 0 ELSE 1 END) AS [CPCount],
        SUM (CASE WHEN ([is_modified] = 1) THEN CAST ([free_space_in_bytes] AS BIGINT) ELSE 0 END) AS [DPFreeSpace],
        SUM (CASE WHEN ([is_modified] = 1) THEN 0 ELSE CAST ([free_space_in_bytes] AS BIGINT) END) AS [CPFreeSpace]
    FROM sys.dm_os_buffer_descriptors
    WHERE [database_id] = DB_ID (''?'')
    GROUP BY [allocation_unit_id]) AS buffers
INNER JOIN sys.allocation_units AS au ON au.[allocation_unit_id] = buffers.[allocation_unit_id]
INNER JOIN sys.partitions AS p ON au.[container_id] = p.[partition_id]
INNER JOIN sys.indexes AS i ON i.[index_id] = p.[index_id] AND p.[object_id] = i.[object_id]
WHERE p.[object_id] > 100 AND ([DPCount] + [CPCount]) > 12800 -- Taking up more than 100MB
ORDER BY [FreeSpaceMB] DESC;
END';
 end try
 begin catch
 end catch

--table row count
begin try
 exec sp_MSforeachdb 'Use ?; insert into DBAWORK..tb_Table_Rows
 SELECT (SELECT DB_NAME()) as [DB_Name]
	  ,QUOTENAME(SCHEMA_NAME(sOBJ.schema_id)) + ''.'' + QUOTENAME(sOBJ.name) AS [TableNameFull]
	  ,(sOBJ.name) AS [TableName]
      ,SUM(sPTN.Rows) AS [RowCount]
	  ,getdate() as [Date]
FROM  sys.objects AS sOBJ
      INNER JOIN sys.partitions AS sPTN ON sOBJ.object_id = sPTN.object_id
WHERE
      sOBJ.type = ''U''
      AND sOBJ.is_ms_shipped = 0x0
      AND index_id < 2 -- 0:Heap, 1:Clustered
GROUP BY 
      sOBJ.schema_id, sOBJ.name
ORDER BY [TableName]'
 end try
 begin catch
 end catch


DROP table #TempMostUsedTbl

--cleanup for unneeded data
delete FROM [DBAWORK].[dbo].[tb_Statistics_History]
  where [DB_Name] = 'tempdb'

--cleanup for systems with too much data for unused tables
if @servername in ('DAXDBS04','DAX-REPLDB01')
BEGIN
delete FROM [DBAWORK].[dbo].[tb_Statistics_History]
  where rowmodctr = 0
END

--delete old history
delete from DBAWORK..tb_Fragmentation_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Statistics_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Most_Used_Table_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Stored_Procedure_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Index_Usage_History
where Date < getdate() - (@dayshistory + 185)

delete from DBAWORK..tb_Stored_Procedure_Execution_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Top_Queries_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Index_Free_Space
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Table_Rows
where Date < getdate() - @dayshistory

GO



SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

--Create bp_io_performance, all work on RDS
CREATE PROCEDURE [dbo].[bp_io_performance] AS

--gather io information, built by Todd Palecek 7/7/16
--exec DBAWORK..bp_io_performance

BEGIN

SET NOCOUNT ON
	
--determine if need a new insert or change since previous after restart
--data is queried every 2 hours so values less than 120 trigger new run
declare @startdatetime as datetime,
		@freshrun as int,
		@threshhold as int,
		@dayshistory    INT

set @startdatetime = (select create_date from master.sys.databases where name ='tempdb')

set @freshrun = datediff(mi, @startdatetime, getdate())

--minutes old to trigger new value inserts
set @threshhold = 120

set @dayshistory = cast((select Item FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_io_performance' and Class='Days') as INT)

--add server to table if doesn't exist
if ((select count(*) from DBAWORK..tb_servers) < 1)
begin
insert into DBAWORK..tb_servers (server_name)
select @@SERVERNAME
end

CREATE TABLE ##tb_SQLServicePerformanceResults
				([row_id] [int] IDENTITY(1,1) NOT NULL,
				serID [int] Null,
				[dbID] [int] Null,
                servername     VARCHAR(50),
				databasename   VARCHAR(300),
				[database_drive] [varchar](1) NULL,
				[database_file_name] [nvarchar](160) NULL, 
				[NumberReads] [bigint] NULL,
				[NumberWrites] [bigint] NULL,
				[MBsRead] [bigint] NULL,
				[MBsWritten] [bigint] NULL,
				[IoStallReadMS] [bigint] NULL,
				[IoStallWriteMS] [bigint] NULL,
				[report_date_time_start] [datetime] NULL,
				[report_date_time_end] [datetime] NULL,
				[TimeStamp] [datetime] NOT NULL
				)
				
INSERT INTO ##tb_SQLServicePerformanceResults(databasename,database_drive,database_file_name,NumberReads,
				NumberWrites,MBsRead,MBsWritten,IoStallReadMS,IoStallWriteMS,report_date_time_start,report_date_time_end,[TimeStamp],servername)
				SELECT [database_name] = DB_NAME([DbId]),
				(SELECT Left(physical_name,1) FROM sys.master_files
				WHERE database_id = [DbId] and FILE_ID = [FileId]) database_drive,
				(SELECT name FROM sys.master_files
				WHERE database_id = [DbId] and FILE_ID = [FileId]) database_file_name,
				[NumberReads],
				[NumberWrites],
				[MBsRead] = [BytesRead] / (1024*1024),
				[MBsWritten] = [BytesWritten] / (1024*1024),
				IoStallReadMS,
				IoStallWriteMS, 
				(select create_date from master.sys.databases where name ='tempdb') as 'Start_Date',
				getdate() as 'End_Date',
				(select create_date from master.sys.databases where name ='tempdb') as 'TimeStamp',
				(select @@SERVERNAME) as server_name
				FROM ::FN_VIRTUALFILESTATS(NULL, NULL)


---insert new databases to tb_servers_databases
INSERT INTO [DBAWORK].[dbo].[tb_Servers_Databases]
           ([serID],[server_name],[database_name])
SELECT S.[serID],S.[server_name],T.databasename
  FROM [DBAWORK].[dbo].[tb_Servers] S
  inner join ##tb_SQLServicePerformanceResults T on S.server_name = t.servername
  left outer join [DBAWORK].[dbo].[tb_Servers_Databases] D on D.serID = S.serID and D.database_name = T.databasename
  where D.database_name is null

---add serID and dbID to temp performance history table
update ##tb_SQLServicePerformanceResults
set serID = D.serID , [dbID] = D.[dbID]
from ##tb_SQLServicePerformanceResults R 
inner join [DBAWORK].[dbo].[tb_Servers_Databases] D on D.server_name = R.servername and D.database_name = R.databasename

---add new database history to history table
insert into [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx] (serID, dbID, database_drive, database_file_name,[NumberReads]
      ,[NumberWrites]
      ,[MBsRead]
      ,[MBsWritten]
      ,[IoStallReadMS]
      ,[IoStallWriteMS]
      ,[report_date_time_start]
      ,[report_date_time_end]
      ,[TimeStamp])
select R.[serID]
	  ,R.[dbID]
	  ,R.[database_drive]
	  ,R.[database_file_name]
	  ,R.[NumberReads]
	  ,R.[NumberWrites]
	  ,R.[MBsRead]
	  ,R.[MBsWritten]
	  ,R.[IoStallReadMS]
	  ,R.[IoStallWriteMS]
	  ,R.[report_date_time_start]
	  ,R.[report_date_time_end]
      ,R.[TimeStamp]
  FROM ##tb_SQLServicePerformanceResults R
  left outer join [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx] S on S.serID = R.serID and S.dbID = R.dbID and r.database_drive = S.database_drive and S.database_file_name = R.database_file_name
  where S.database_file_name is null and R.serID is not null


  begin
	if @freshrun <= @threshhold
    ---select most recent performance entry ---run this one after server has been restarted
  insert into [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx] (serID, dbID, database_drive, database_file_name,[NumberReads]
      ,[NumberWrites]    ,[MBsRead]     ,[MBsWritten]     ,[IoStallReadMS]     ,[IoStallWriteMS]      ,[report_date_time_start]
      ,[report_date_time_end]      ,[TimeStamp])
  select P.[serID]	  ,P.[dbID] 	  ,P.[database_drive] 	  ,P.[database_file_name]
	  ,P.[NumberReads] 'Reads'
	  ,P.[NumberWrites] 'Writes'
	  ,P.[MBsRead]  'MBsRead'
	  ,P.[MBsWritten] 'MBsWritten'
	  ,P.[IoStallReadMS]  'IOStallReadMS'
	  ,P.[IoStallWriteMS]  'IOStallWriteMS'
	  ,P.[report_date_time_start] 'StartDate'
	  ,P.[report_date_time_end]
	  ,P.[TimeStamp]
  FROM ##tb_SQLServicePerformanceResults P

  else
  ---select most recent performance entry 
  insert into [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx] (serID, dbID, database_drive, database_file_name,[NumberReads]
      ,[NumberWrites]    ,[MBsRead]     ,[MBsWritten]     ,[IoStallReadMS]     ,[IoStallWriteMS]      ,[report_date_time_start]
      ,[report_date_time_end]      ,[TimeStamp])
  select P.[serID]	  ,P.[dbID] 	  ,P.[database_drive] 	  ,P.[database_file_name]
	  ,P.[NumberReads]-Q.NumberReads 'Reads'
	  ,P.[NumberWrites] - Q.NumberWrites 'Writes'
	  ,P.[MBsRead] - Q.[MBsRead] 'MBsRead'
	  ,P.[MBsWritten] - Q.[MBsWritten] 'MBsWritten'
	  ,P.[IoStallReadMS] - Q.[IoStallReadMS] 'IOStallReadMS'
	  ,P.[IoStallWriteMS] - Q.[IoStallWriteMS] 'IOStallWriteMS'
	  ,Q.[report_date_time_end] 'StartDate'
	  ,P.[report_date_time_end]
	  ,P.[TimeStamp]
  FROM ##tb_SQLServicePerformanceResults P
  inner join (select O.[serID]
	,O.[dbID]
	  ,O.[database_drive]
	  ,O.[database_file_name]
	  ,sum(O.[NumberReads]) 'NumberReads'
	  ,sum(O.[NumberWrites]) 'NumberWrites'
		,sum(O.[MBsRead]) 'MBsRead'
		,sum(O.[MBsWritten]) 'MBsWritten'
		,sum(O.[IoStallReadMS]) 'IoStallReadMS'
		,sum(O.[IoStallWriteMS]) 'IoStallWriteMS'
		,max(O.[report_date_time_end]) 'report_date_time_end'
  FROM 	(select R.[serID]
		,R.[dbID]
		,R.[database_drive]
		,R.[database_file_name]
		,R.[NumberReads]
		,R.[NumberWrites]
		,R.[MBsRead]
		,R.[MBsWritten]
		,R.[IoStallReadMS]
		,R.[IoStallWriteMS]
		,R.[report_date_time_end]
  FROM [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx] R
  inner join ##tb_SQLServicePerformanceResults A on A.serID = R.serID and A.[dbID] = R.[dbID] 
  and R.database_drive = A.database_drive and R.database_file_name = A.database_file_name
  and R.report_date_time_start >= A.[timestamp] and R.report_date_time_end < A.report_date_time_end) O
  group by O.[serID]
      ,O.[dbID]
      ,O.[database_drive]
      ,O.[database_file_name]) Q
   on Q.serID = P.serID and Q.[dbID] = P.[dbID] and Q.database_drive = P.database_drive and Q.database_file_name = P.database_file_name
END

update [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx]
set  [TotalIO] = [NumberReads] + [NumberWrites], [TotalMBs] = [MBsRead] + [MBsWritten], [IoStallMS] = [IoStallReadMS] + [IoStallWriteMS],
[AvgStallPerReadIO] = case [NumberReads] when 0 then 0 else [IoStallReadMS]/[NumberReads] end,
[AvgStallPerWriteIO] = case [NumberWrites] when 0 then 0 else [IoStallWriteMS]/[NumberWrites] end

update [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx]
set  [AvgStallPerIO] = case [TotalIO] when 0 then 0 else [IoStallMS]/[TotalIO] end

--delete negative values
delete FROM [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx]
  where TotalIO < 0

delete FROM [DBAWORK].[dbo].[tb_monitor_sql_database_performance_hx]
  where AvgStallPerWriteIO < 0

delete from DBAWORK..[tb_monitor_sql_database_performance_hx]
  where [report_date_time_end] < getdate() - @dayshistory

drop table ##tb_SQLServicePerformanceResults

SET NOCOUNT OFF
END

GO



SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create proc [dbo].[bp_long_run_SP] as

declare @Offset decimal(9,5),
		@Email nvarchar(250)

set @Offset = cast((select Item FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_long_run_SP' and Class='Minutes') as decimal(9,5))/1440
set @Email = (SELECT Item FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='ALL' and Class='DBA Email')

--exec DBAWORK..[bp_long_run_SP]

--only history for last 2 hours to review,run job every 30 minutes
delete from DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk where [Date] < getdate()-@Offset;

delete from DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk_Prob;

--remove specific sps
delete DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk 
where SP_Name = (select Item FROM DBAWORK.[dbo].[tb_Parameters] WHERE SP_Name='bp_long_run_SP' and Class='Exclusion')

--qs.last_elapsed_time is reported in microseconds but only accurate to milliseconds, the avg exec time is calculated from all time and all executions so is different
begin try
 INSERT INTO DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk
 EXEC sp_MSforeachdb 'USE [?]; IF DB_ID(''?'') > 4
 BEGIN
 SELECT (SELECT DB_NAME()) as [DB_Name], p.name AS [SP_Name], qs.last_elapsed_time,qs.last_execution_time--, getdate() as [Date]
FROM sys.procedures AS p
INNER JOIN sys.dm_exec_procedure_stats AS qs
ON p.[object_id] = qs.[object_id]
WHERE qs.database_id = DB_ID()
and qs.last_execution_time >= getdate()-1
 END'
 end try
 begin catch
 end catch;


--only SP that have more than one long run
with Long_SP (DB_Name, SP_Name, last_elapsed_time, Mean, StandardDev, UpperBound, SampleSize, Date)
as (
SELECT  distinct      H.DB_Name, H.[SP_Name], H.last_elapsed_time, S.Mean, S.StandardDev, S.UpperBound, S.SampleSize, H.[Date]
FROM          DBAWORK.dbo.vw_AnalysisUpperLowerBoundsSP AS S INNER JOIN
                             (SELECT        [DB_Name], [SP_Name], last_elapsed_time, [Date]
                               FROM         DBAWORK.dbo.tb_Stored_Procedure_Execution_Daily_Chk
                               WHERE        (last_elapsed_time > 3)) AS H ON H.DB_Name = S.DB_Name AND H.[SP_Name] = S.[SP Name]
WHERE        H.last_elapsed_time > 1000 and (H.last_elapsed_time > S.UpperBound)
)
insert into DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk_Prob
select SP_Name
from Long_SP
group by SP_Name
having count(SP_Name) > 1;


if ((select count(*) from DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk_Prob) > 0)
EXEC msdb..sp_send_dbmail --@profile_name='DAXDBS04_Mail',
@recipients=@Email, --'DL-DataServices@silverstarbrands.com','tpalecek@silverstarbrands.com'
@subject='Long Running Stored Procs',
@query= 'SELECT  distinct top 1000  (rtrim(ltrim(H.[DB_Name])) + ''.'' + rtrim(ltrim(H.[SP_Name]))) SPName, H.last_elapsed_time, S.Mean, cast(S.UpperBound as int) as UpprBnd, H.[Date]
	FROM          DBAWORK.dbo.vw_AnalysisUpperLowerBoundsSP AS S 
	INNER JOIN    DBAWORK.dbo.tb_Stored_Procedure_Execution_Daily_Chk H ON H.DB_Name = S.DB_Name AND H.[SP_Name] = S.[SP Name]
	inner join    DBAWORK..tb_Stored_Procedure_Execution_Daily_Chk_Prob P on P.[SP_Name] = H.[SP_Name]
	WHERE H.last_elapsed_time > 1000 and (H.last_elapsed_time > S.UpperBound)
	order by (rtrim(ltrim(H.[DB_Name])) + ''.'' + rtrim(ltrim(H.[SP_Name]))),H.[Date] DESC' --service account doesn't have access to run query
GO




SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[bp_cpu_utilization] AS

--track history of memory, cpu, transactions built by Todd Palecek toddpalecek@gmail.com 8/5/2015
--exec DBAWORK..bp_cpu_utilization

BEGIN

SET NOCOUNT ON

create table ##temp_Memory(
	[Total_Physical_Memory_KB] bigint NULL DEFAULT 0,
	[Total_Physical_Memory_KB_Available] bigint NULL DEFAULT 0,
	[Total_Virtual_Memory_KB] bigint NULL DEFAULT 0,
	[Total_Virtual_Memory_KB_Available] bigint NULL DEFAULT 0,
	[Total_Page_File_Memory_KB] bigint NULL DEFAULT 0,
	[Total_Page_File_Memory_KB_Available] bigint NULL DEFAULT 0,
	[Total_System_Cache_Memory_KB_Available] bigint NULL DEFAULT 0,
	[Mem_Needed_KB_Per_Current_Workload] bigint NULL DEFAULT 0,
	[Mem_Used_KB_Maintaining_Connections] bigint NULL DEFAULT 0,
	[Mem_Used_KB_Locks] bigint NULL DEFAULT 0,
	[Mem_Used_KB_Dynamic_Cache] bigint NULL DEFAULT 0,
	[Mem_Used_KB_Query_Optimization] bigint NULL DEFAULT 0,
	[Mem_Used_KB_Hash_Sort_Index_Operations] bigint NULL DEFAULT 0,
	[Mem_Used_KB_Cursors] bigint NULL DEFAULT 0,
	[Mem_Used_KB_SQLServer] bigint NULL DEFAULT 0,
	[Locked_Pages_Used_SQLServer_KB] bigint NULL DEFAULT 0,
	[Total_VAS_KB] bigint NULL DEFAULT 0,
	[Memory_Grants_Pending] bigint NULL DEFAULT 0,
	[System_High_Memory_Signal_State] int DEFAULT 0,
	[System_Low_Memory_Signal_State] int DEFAULT 0,
	[Process_Physical_Memory_Low] int DEFAULT 0,
	[Process_Virtual_Memory_Low] int DEFAULT 0,
	[Free_List_Stalls_Per_Sec] bigint NULL DEFAULT 0,
	[Checkpoint_Pages_Per_Sec] bigint NULL DEFAULT 0,
	[Lazy_Writes_Per_Sec] bigint NULL DEFAULT 0,
	[Date] [datetime] NULL DEFAULT 0
) ON [PRIMARY]


DECLARE @ts_now			bigint
DECLARE @dayshistory    INT,
		@date2 datetime,
		@cntr_value2 bigint,
		@date1 datetime,
		@cntr_value1 bigint,
		@seconds int,
		@batches bigint,
		@pg_size INT, 
		@Instancename varchar(50),
		@product_version nvarchar(20),
		@statement1 nvarchar(200),
		@statement2 nvarchar(200)
--for job history
 declare @year as nvarchar(4)
 declare @month as nvarchar(3)
 declare @day as nvarchar(3)
 declare @hour as int
 declare @hourCur as int
 declare @run_date as nvarchar(8)
 declare @offset decimal (8,6) 
 --ssrs report job history
declare @ReportServerDB as nvarchar(75)
declare @SQLScript varchar(max)
DECLARE @CREATE_TEMPLATE VARCHAR(MAX)
--ssis report history
declare @SSISServerDB as nvarchar(75)
--RDS check
declare @RDS bit
--dist check
declare @Dist bit

select @ts_now = ms_ticks from sys.dm_os_sys_info 

set @dayshistory = 180

--job history
 set @offset = .0833333 -- 2 hours
 
 set @year = (select datepart(yyyy,getdate()-@offset))
 set @month = (select datepart(mm,getdate()-@offset))
 set @month = '0' + @month
 set @month = (right(@month, 2))
 set @day = (select datepart(dd,getdate()-@offset))
 set @day = '0' + @day
 set @day = (right(@day,2))
 set @run_date = (select @year + @month + @day)
 set @hourCur = (datepart(hh,getdate()))
 set @hour = (@hourCur-(@offset*24))
 begin
  if @offset >= 1 
  set @hour = 0
 end
 begin
  if @offset >= 1 
  set @hourCur = 24
 end
 set @hourCur = @hourCur * 10000
 set @hour = @hour * 10000

SELECT @pg_size = low from master..spt_values where number = 1 and type = 'E' 

--check if RDS
set @RDS = 0
if (select count(*) from sys.databases where name = 'rdsadmin')>0
set @RDS =1;

--check if Distributor
set @Dist = 0
if (select count(*) from sys.databases where name = 'distribution')>0
set @Dist =1;

--works in RDS
-- Extract perfmon counters to a temporary table
IF OBJECT_ID('tempdb..#perfmon_counters') is not null DROP TABLE #perfmon_counters
SELECT * INTO #perfmon_counters FROM sys.dm_os_performance_counters

--works in RDS
-- Get SQL Server instance name
SELECT @Instancename = LEFT([object_name], (CHARINDEX(':',[object_name]))) FROM #perfmon_counters WHERE counter_name = 'Buffer cache hit ratio' 

set @product_version = cast((SELECT SERVERPROPERTY('productversion')) as nvarchar(20))

--works in RDS
--history seems variable depending on server, going with a 2 hour run
insert into DBAWORK..tb_cpu_history
select 
	dateadd(ms, -1 * (@ts_now - [timestamp]), GetDate()) as Date, 
	SQLProcessUtilization,
	SystemIdle,
	100 - SystemIdle - SQLProcessUtilization as OtherProcessUtilization
	from (
		select 
		record.value('(./Record/@id)[1]', 'int') as record_id,
		record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') as SystemIdle,
		record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') as SQLProcessUtilization,
		timestamp
		from (
			select timestamp, convert(xml, record) as record 
			from sys.dm_os_ring_buffers 
			where ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
			and record like '%<SystemHealth>%') as x
		) as y 
		where dateadd(ms, -1 * (@ts_now - [timestamp]), GetDate()) > getdate() - .08333333  --only returns last 2 hours
	order by record_id desc

--works in RDS
--batch requests per second is sql speedometer 
insert into DBAWORK..tb_batchrequests_history
SELECT object_name, counter_name, cntr_value, getdate() as Date, 0, 0 FROM sys.dm_os_performance_counters  --For per-second counters, this value is cumulative. 
where counter_name like '%Batch Requests/sec%'

set @date1 = (SELECT top 1 A.Date from (SELECT top 2 [Date] FROM [DBAWORK].[dbo].[tb_batchrequests_history] order by Date DESC) A order by A.Date)
set @cntr_value1 = (SELECT top 1 A.cntr_value from (SELECT top 2 [Date],[cntr_value] FROM [DBAWORK].[dbo].[tb_batchrequests_history] order by Date DESC) A order by A.Date)

set @date2 = (SELECT top 1 [Date] FROM [DBAWORK].[dbo].[tb_batchrequests_history] order by Date DESC)
set @cntr_value2 = (SELECT top 1 [cntr_value] FROM [DBAWORK].[dbo].[tb_batchrequests_history] order by Date DESC)

set @seconds = datediff(ss, @date1, @date2)
set @batches = @cntr_value2 - @cntr_value1

--tmp 1/8/16 to catch if no recent data in table
if @batches < 0
begin
set @batches = @cntr_value1
set @seconds = 0
end

update [DBAWORK].[dbo].[tb_batchrequests_history]
set seconds = @seconds, requests = @batches
where Date = @date2


insert into DBAWORK..[tb_PacketActivity] (PacketsReceivedBase,PacketsSentBase,PacketErrorsBase,Date)
select @@Pack_Received,@@PACK_SENT,@@PACKET_ERRORS, getdate()


--distribution command tracking 
if @Dist = 1
BEGIN
 --declare @offset decimal (8,6) 
 --set @offset = .666664 --.0833333 -- 2 hours
IF OBJECT_ID('tempdb..#tb_distribution_commands_stg', 'U') IS NOT NULL 
DROP TABLE tempdb..#tb_distribution_commands_stg;

IF OBJECT_ID('tempdb..#tb_distribution_commands_stg2', 'U') IS NOT NULL 
DROP TABLE tempdb..#tb_distribution_commands_stg2;

CREATE TABLE #tb_distribution_commands_stg(
	[name] [nvarchar](100) NOT NULL,
	[id] [int] NOT NULL,
	[start_time] [datetime] NOT NULL,
	[runstatus] [int] NOT NULL,
	[time] [datetime] NOT NULL,
	[delivered_commands] [int] NOT NULL,
	[seconds] [int] NOT NULL,
	[commands] bigint NOT NULL,
	[commands_per_Minute] decimal(10,2) NOT NULL,
	[DateKey] [int] NULL,
	[Hour] [int] NULL,
	[Minute] [int] NULL,
	RowNum int NOT NULL,
	UpdateFlag bit not NULL
) ON [PRIMARY]

CREATE TABLE #tb_distribution_commands_stg2(
	[id] [int] NOT NULL,
	[start_time] [datetime] NOT NULL,
	[time] [datetime] NOT NULL,
	[delivered_commands] [bigint] NOT NULL,
	RowNum int NOT NULL
) ON [PRIMARY]

insert into #tb_distribution_commands_stg
SELECT A.name,A.id, H.start_time, H.runstatus, H.time, H.delivered_commands, 0 'seconds', 0 'commands', 0 'commands_per_Minute',
0 'DateKey' , 0 'Hour', 0 'Minute'
,row_number() over (partition by A.id order by time DESC) 'RowNum', 0 'Flag'
  FROM [distribution].[dbo].[MSdistribution_history] H
  inner join [distribution].[dbo].MSdistribution_agents A on A.id = H.agent_id
  where delivered_commands > 0
    and time > getdate() - @offset 

	delete #tb_distribution_commands_stg
	where RowNum = 1;

	insert into #tb_distribution_commands_stg2
	 select  id, [start_time], [time], delivered_commands, RowNum-1 'RowNum'
	  from #tb_distribution_commands_stg
	
  update #tb_distribution_commands_stg
  set [seconds] = (select datediff(ss, d.time, t.time)), commands = t.delivered_commands - d.delivered_commands 
	from #tb_distribution_commands_stg t
	inner join #tb_distribution_commands_stg2 d
	on d.RowNum = t.RowNum 
	   and d.[id] = t.[id] 
	   and d.[start_time] = t.[start_time]

	--handle after reboot
	  	 update #tb_distribution_commands_stg
		 set commands = 0
		 where commands < 0

	  --multiplied by 100 to avoid division by zero
	   	 update #tb_distribution_commands_stg
		 set commands_per_Minute = (commands*100) /((seconds*100)/60)
		 where seconds > 0

		 update #tb_distribution_commands_stg
		 set Hour = datepart(hh,time), Minute = datepart(mi,time), DateKey = CAST(CONVERT(VARCHAR(8), time, 112) AS INT)

	 insert into DBAWORK.[dbo].[tb_distribution_commands]
	  select [name]
      ,[id]
      ,[start_time]
      ,[runstatus]
      ,[time]
      ,[delivered_commands]
      ,[seconds]
	  ,[commands]
      ,[commands_per_Minute]
	  ,DateKey
	  ,Hour
	  ,Minute
	  from #tb_distribution_commands_stg;

	  	truncate table #tb_distribution_commands_stg
		truncate table #tb_distribution_commands_stg2

		--need to update the first record from the 2 hour run
		insert into #tb_distribution_commands_stg
		SELECT [name],[id]
      ,[start_time]
      ,[runstatus]
      ,[time]
      ,[delivered_commands]
      ,[seconds]
      ,[commands]
      ,[commands_per_Minute]
	 ,0 as 'DateKey'
	,0 as 'Hour'
	,0 as 'Minute'
	  ,row_number() over (partition by id order by time DESC) 'RowNum'
	  ,0 'Flag'
  FROM [DBAWORK].[dbo].[tb_distribution_commands]
  where time > getdate()-.5

  	insert into #tb_distribution_commands_stg2
	 select  id, [start_time], [time], delivered_commands, RowNum-1 'RowNum'
	  from #tb_distribution_commands_stg

	update #tb_distribution_commands_stg
	set UpdateFlag = 1
	where Seconds = 0

    update #tb_distribution_commands_stg
 set [seconds] = (select datediff(ss, d.time, t.time)), commands = t.delivered_commands - d.delivered_commands 
	from #tb_distribution_commands_stg t
	inner join #tb_distribution_commands_stg2 d
	on d.RowNum = t.RowNum 
	   and d.[id] = t.[id] 
	   and d.[start_time] = t.[start_time]
	   
	  delete #tb_distribution_commands_stg
	  where UpdateFlag is null

	  	 update #tb_distribution_commands_stg
		 set commands_per_Minute = (commands*100) /((seconds*100)/60)
		 where seconds > 0

	  update [DBAWORK].[dbo].[tb_distribution_commands]
	  set seconds = t.seconds, commands = t.commands, commands_per_Minute = t.commands_per_Minute
	  	from #tb_distribution_commands_stg t
	inner join [DBAWORK].[dbo].[tb_distribution_commands] d
	   on d.[id] = t.[id] 
	   and d.[start_time] = t.[start_time]
	   and d.time = t.time

	   	drop table #tb_distribution_commands_stg
		drop table #tb_distribution_commands_stg2
END


--memory tracking
if left(@product_version,2) in ('7.','8.','9.','10')
BEGIN
set @statement1 = 'insert into ##temp_Memory(Total_Physical_Memory_KB) SELECT CEILING(physical_memory_in_bytes/8192) FROM sys.dm_os_sys_info'
set @statement2 = 'insert into ##temp_Memory(Total_Virtual_Memory_KB) SELECT CEILING(virtual_memory_in_bytes/8192) FROM sys.dm_os_sys_info'
END
else
BEGIN
set @statement1 = 'insert into ##temp_Memory(Total_Physical_Memory_KB) SELECT physical_memory_kb FROM sys.dm_os_sys_info'
set @statement2 = 'insert into ##temp_Memory(Total_Virtual_Memory_KB) SELECT virtual_memory_kb FROM sys.dm_os_sys_info'
END

exec (@statement1)
exec (@statement2)

insert into ##temp_Memory(Mem_Needed_KB_Per_Current_Workload) SELECT (cntr_value) as Mem_Needed_KB_Per_Current_Workload FROM #perfmon_counters WHERE counter_name = 'Target Server Memory (KB)'
insert into ##temp_Memory(Mem_Used_KB_Maintaining_Connections) SELECT (cntr_value) as Mem_Used_KB_Maintaining_Connections FROM #perfmon_counters WHERE counter_name = 'Connection Memory (KB)'
insert into ##temp_Memory(Mem_Used_KB_Locks) SELECT (cntr_value) as Mem_Used_KB_Locks FROM #perfmon_counters WHERE counter_name = 'Lock Memory (KB)'
insert into ##temp_Memory(Mem_Used_KB_Dynamic_Cache) SELECT (cntr_value) as Mem_Used_KB_Dynamic_Cache FROM #perfmon_counters WHERE counter_name = 'SQL Cache Memory (KB)'
insert into ##temp_Memory(Mem_Used_KB_Query_Optimization) SELECT (cntr_value) as Mem_Used_KB_Query_Optimization FROM #perfmon_counters WHERE counter_name = 'Optimizer Memory (KB) '
insert into ##temp_Memory(Mem_Used_KB_Hash_Sort_Index_Operations) SELECT (cntr_value) as Mem_Used_KB_Hash_Sort_Index_Operations FROM #perfmon_counters WHERE counter_name = 'Granted Workspace Memory (KB) '
insert into ##temp_Memory(Mem_Used_KB_Cursors) SELECT (cntr_value) as Mem_Used_KB_Cursors FROM #perfmon_counters WHERE counter_name = 'Cursor memory usage' and instance_name = '_Total'
insert into ##temp_Memory(Free_List_Stalls_Per_Sec) SELECT cntr_value as [Free list stalls/sec] FROM #perfmon_counters WHERE object_name=@Instancename+'Buffer Manager' and counter_name = 'Free list stalls/sec'
insert into ##temp_Memory(Checkpoint_Pages_Per_Sec) SELECT cntr_value as [Checkpoint pages/sec] FROM #perfmon_counters WHERE object_name=@Instancename+'Buffer Manager' and counter_name = 'Checkpoint pages/sec'
insert into ##temp_Memory(Lazy_Writes_Per_Sec) SELECT cntr_value as [Lazy writes/sec] FROM #perfmon_counters WHERE object_name=@Instancename+'Buffer Manager' and counter_name = 'Lazy writes/sec'
insert into ##temp_Memory(Memory_Grants_Pending) SELECT cntr_value as [Memory_Grants_Pending] FROM #perfmon_counters WHERE object_name=@Instancename+'Memory Manager' and counter_name = 'Memory Grants Pending'
insert into ##temp_Memory(Total_Physical_Memory_KB_Available) select available_physical_memory_kb from sys.dm_os_sys_memory
insert into ##temp_Memory(Total_Page_File_Memory_KB) select total_page_file_kb from sys.dm_os_sys_memory
insert into ##temp_Memory(Total_Page_File_Memory_KB_Available) select available_page_file_kb from sys.dm_os_sys_memory
insert into ##temp_Memory(Total_System_Cache_Memory_KB_Available) select system_cache_kb from sys.dm_os_sys_memory
insert into ##temp_Memory(System_High_Memory_Signal_State) select system_high_memory_signal_state from sys.dm_os_sys_memory
insert into ##temp_Memory(System_Low_Memory_Signal_State) select system_low_memory_signal_state from sys.dm_os_sys_memory
insert into ##temp_Memory(Total_Virtual_Memory_KB_Available) select virtual_address_space_available_kb from sys.dm_os_process_memory
insert into ##temp_Memory(Mem_Used_KB_SQLServer) select physical_memory_in_use_kb from sys.dm_os_process_memory
insert into ##temp_Memory(Process_Physical_Memory_Low) select process_physical_memory_low from sys.dm_os_process_memory
insert into ##temp_Memory(Process_Virtual_Memory_Low) select process_virtual_memory_low from sys.dm_os_process_memory
insert into ##temp_Memory(Total_VAS_KB) select total_virtual_address_space_kb from sys.dm_os_process_memory
insert into ##temp_Memory(Locked_Pages_Used_SQLServer_KB) select locked_page_allocations_kb from sys.dm_os_process_memory

insert into DBAWORK..tb_Memory_History
select max(Total_Physical_Memory_KB) as Total_Physical_Memory_KB,
	max(Total_Physical_Memory_KB_Available) as Total_Physical_Memory_KB_Available,
	max(Total_Virtual_Memory_KB) as Total_Virtual_Memory_KB,  --pre 2012 is wrong
	max(Total_Virtual_Memory_KB_Available) as Total_Virtual_Memory_KB_Available, --pre 2012 is wrong
	max(Total_Page_File_Memory_KB) as Total_Page_File_Memory_KB,
	max(Total_Page_File_Memory_KB_Available) as Total_Page_File_Memory_KB_Available,
	max(Total_System_Cache_Memory_KB_Available) as Total_System_Cache_Memory_KB_Available,
	max(Mem_Needed_KB_Per_Current_Workload) as Mem_Needed_KB_Per_Current_Workload,
	max(Mem_Used_KB_Maintaining_Connections) as Mem_Used_KB_Maintaining_Connections,
	max(Mem_Used_KB_Locks) as Mem_Used_KB_Locks,
	max(Mem_Used_KB_Dynamic_Cache) as Mem_Used_KB_Dynamic_Cache,
	max(Mem_Used_KB_Query_Optimization) as Mem_Used_KB_Query_Optimization,
	max(Mem_Used_KB_Hash_Sort_Index_Operations) as Mem_Used_KB_Hash_Sort_Index_Operations,
	max(Mem_Used_KB_Cursors) as Mem_Used_KB_Cursors,
	max(Mem_Used_KB_SQLServer) as Mem_Used_KB_SQLServer,
	max(Locked_Pages_Used_SQLServer_KB) as Locked_Pages_Used_SQLServer_KB,
	max(Total_VAS_KB) as Total_VAS_KB,  --see if matches to Total_Virtual_Memory_KB
	max(Memory_Grants_Pending) as Memory_Grants_Pending,
	max(System_High_Memory_Signal_State) as System_High_Memory_Signal_State,
	max(System_Low_Memory_Signal_State) as System_Low_Memory_Signal_State,
	max(Process_Physical_Memory_Low) as Process_Physical_Memory_Low,
	max(Process_Virtual_Memory_Low) as Process_Virtual_Memory_Low,
	max(Free_List_Stalls_Per_Sec) as Free_List_Stalls_Per_Sec,
	max(Checkpoint_Pages_Per_Sec) as Checkpoint_Pages_Per_Sec,
	max(Lazy_Writes_Per_Sec) as Lazy_Writes_Per_Sec,
	getdate() as Date  from ##temp_Memory

-- Page Life Expectancy (PLE) value for default instance
INSERT INTO [DBAWORK].[dbo].[tb_Page_Life_Expectancy]
SELECT cntr_value AS [Page Life Expectancy], getdate()
FROM sys.dm_os_performance_counters
WHERE OBJECT_NAME = 'SQLServer:Buffer Manager' -- Modify this if you have named instances
AND counter_name = 'Page life expectancy';

-- Get Buffer cache hit ratio (higher is better)
begin try
INSERT INTO [DBAWORK].[dbo].[tb_Buffer_Cache_Hit_Ratio]
SELECT ROUND(CAST(A.cntr_value1 AS NUMERIC) / 
CAST(B.cntr_value2 AS NUMERIC),3) AS [Buffer Cache Hit Ratio], getdate()
FROM ( SELECT cntr_value AS [cntr_value1]
FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:Buffer Manager' -- Modify this if you have named instances
AND counter_name = 'Buffer cache hit ratio'
) AS A,
(SELECT cntr_value AS [cntr_value2]
FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:Buffer Manager' -- Modify this if you have named instances
AND counter_name = 'Buffer cache hit ratio base'
) AS B
 end try
 begin catch
 end catch

--does not work in AWS RDS 3/7/17, below select could be modified to caputre
--SELECT [job_name],0 as JobFailStep,[message],[run_requested_date],[stop_execution_date],[run_status],getdate() FROM [DBAWORK].[dbo].[SQL_agent_job_status]
--job history 10/18/16
-- declare @offset decimal (8,6) 
-- set @offset = .0833333 -- 2 hours
IF @RDS = 0
BEGIN
INSERT INTO DBAWORK.dbo.tb_Jobs_hx(JobName,JobFailStep,JobFailMessage,                                                                                                     
                                  RunDateTime,JobDurationSeconds,RunStatus,Owner,Source,Date)  
SELECT  SUBSTRING(a.job_name, 1, 60)               as [job_name],                                 
        a.step_id                                 as [job_fail_step],                                
        a.[Error Message] as [job_fail_message],	
		cast((LEFT(CAST(a.run_date      AS CHAR(8)),4) + '-' + 
		SUBSTRING(CAST(a.run_date AS CHAR(8)),5,2) + '-'   +                                    
        RIGHT(CAST(a.run_date     AS CHAR(8)),2) + ' '   +                                    
		LEFT(RIGHT('000000'      + CAST(a.run_time AS VARCHAR(10)),6),2)    + ':'   +                                    
        SUBSTRING(RIGHT('000000' + CAST(a.run_time AS VARCHAR(10)),6),3,2)   + ':'   +                                    
        RIGHT(RIGHT('000000'     + CAST(a.run_time AS VARCHAR(10)),6),2)) as datetime)        as 'run_date_time2',                        
	    cast(LEFT(RIGHT('000000'      + CAST(a.run_duration AS VARCHAR(10)),6),2) as int) * 3600   +                                     
        cast(SUBSTRING(RIGHT('000000' + CAST(a.run_duration AS VARCHAR(10)),6),3,2) as int) * 60  +                                    
        cast(RIGHT(RIGHT('000000'     + CAST(a.run_duration AS VARCHAR(10)),6),2) as int) as [job_duration_seconds],                     
		a.run_status,    
		null as Owner,
		'SQLAgent' as 'Source',
		getdate()                 
	FROM   
   (SELECT  d.server    as sql_server_name,                                                    
			a.job_id    	as job_id,                                                             
            a.name       	as job_name,                                                           
            d.run_date  	as run_date,                                                           
            d.run_time     	as run_time,                                                           
            d.run_duration 	as run_duration,                                                       
            d.instance_id   as job_instance_id,  
			SUBSTRING(d.message, CHARINDEX('.', d.message, 1) + 2, 45) as [Error Message],	 
			d.step_id, 																							 
			d.run_status
			,dateadd(s,d.run_duration,dateadd(mi,cast(substring(right('000000' + cast(run_time as nvarchar(6)),6),3,2) as int),dateadd(hh,cast(left(right('000000' + cast(run_time as nvarchar(6)),6),2) as int),dateadd(ss,cast(right(right('000000' + cast(run_time as nvarchar(6)),6),2) as int),cast(left(d.run_date,4) + '-' + substring(cast(d.run_date as nvarchar(8)),5,2) + '-' + right(d.run_date,2) as datetime))))) as EndDateTime
            FROM    msdb.dbo.sysjobs as a                                         
            LEFT JOIN  msdb.dbo.sysjobhistory  as d  on a.job_id = d.job_id   
			--changed 1/11/17 to capture based specifically on end time, 1/18/17 changed to actually use seconds
			where dateadd(s,(cast(LEFT(RIGHT('000000'      + CAST(d.run_duration AS VARCHAR(10)),6),2) as int) * 3600   +                                     
        cast(SUBSTRING(RIGHT('000000' + CAST(d.run_duration AS VARCHAR(10)),6),3,2) as int) * 60  +                                    
        cast(RIGHT(RIGHT('000000'     + CAST(d.run_duration AS VARCHAR(10)),6),2) as int)),
			dateadd(mi,cast(substring(right('000000' + cast(run_time as nvarchar(6)),6),3,2) as int),dateadd(hh,cast(left(right('000000' + cast(run_time as nvarchar(6)),6),2) as int),dateadd(ss,cast(right(right('000000' + cast(run_time as nvarchar(6)),6),2) as int),cast(left(d.run_date,4) + '-' + substring(cast(d.run_date as nvarchar(8)),5,2) + '-' + right(d.run_date,2) as datetime))))) >= getdate()-@offset
     	)    a
END



--10/18/16 ssrs job history
--need to code the db name for now
set @ReportServerDB = (select name from sys.databases where name like '%ReportServer%' and name not like '%Temp%')

if len(@ReportServerDB) > 2 
BEGIN
INSERT INTO DBAWORK.dbo.tb_Jobs_hx(JobName,JobFailStep,JobFailMessage,                                                                                                
                                     RunDateTime,JobDurationSeconds,RunStatus,
									 Owner,Source,Date)  
	SELECT [ReportPath]
	  ,1 as JobFailStep
      ,[Parameters]
      ,[TimeStart]
   	  ,([TimeDataRetrieval]+[TimeProcessing]+[TimeRendering])/1000
      ,case when [Status] = 'rsSuccess' then 1 else 0 end as run_status
	  ,[UserName]																					 
	  ,'SSRS'
	  ,getdate()
  FROM [ReportServer].[dbo].[ExecutionLog2] (nolock)
  where TimeEnd > getdate()-@offset
  order by [TimeStart] DESC
END

--ssis history
set @SSISServerDB = (select name from sys.databases where name like '%SSIS%')

if len(@SSISServerDB) > 2 
BEGIN
BEGIN TRY
INSERT INTO DBAWORK.dbo.tb_Jobs_hx(JobName,JobFailStep,JobFailMessage,                                                                                                
                                     RunDateTime,JobDurationSeconds,RunStatus,
									 Owner,Source,Date)  
  SELECT  [execution_path]
  	  ,1 as JobFailStep
	  ,'' as job_fail_message
      ,cast([start_time] as datetime)
      ,[execution_duration]/1000
      ,case when [execution_result] = 0 then 1 else 0 end
	  ,null as Owner
	  ,'SSIS' as 'Source'
	  ,getdate()
  FROM [SSISDB].[internal].[executable_statistics] (nolock)
  where end_time > getdate()-@offset
   end try
 begin catch
 end catch
END

delete from DBAWORK..tb_cpu_history
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_batchrequests_history
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Memory_History
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Page_Life_Expectancy  
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Buffer_Cache_Hit_Ratio 
where Date < getdate() - @dayshistory

delete from DBAWORK..tb_Jobs_hx
where Date < getdate() - @dayshistory

delete from DBAWORK..[tb_PacketActivity]
where Date < getdate() - @dayshistory

drop table ##temp_Memory

--call io history create
exec DBAWORK..bp_io_performance

SET NOCOUNT OFF
END

GO



SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[bp_Index_Rebuild_Targeted] @MaxDOP nvarchar(2), @RecordCount INT, @IndexRecordCount INT, @Online bit = 1
AS

--exec bp_Index_Rebuild_Targeted 2, 5000, 20000, 0

/*has issue experiencing with running slow - no resolution though
http://social.technet.microsoft.com/Forums/sqlserver/es-ES/71b840db-cf9c-46a3-89df-c44e587d8d32/sysdmdbindexphysicalstats-serious-performance-issue?forum=transactsql
*/

DECLARE @tsql NVARCHAR(MAX)  
DECLARE @RowCount INT
DECLARE @DatabaseName VARCHAR(1000)
DECLARE @DatabaseTable VARCHAR(1000)
DECLARE @fillfactor INT
DECLARE	@IndexEvalTable TABLE (ID INT IDENTITY,	DatabaseID INT,	DatabaseName VARCHAR(100), DatabaseTableID INT,	DatabaseTable VARCHAR(200),RecordCount BIGINT,	TotalAccesses BIGINT,TotalReads BIGINT)
DECLARE	@IndexEvalTable2 TABLE (ID INT IDENTITY,DatabaseID INT,	DatabaseName VARCHAR(100),	DatabaseTableID INT,DatabaseTable VARCHAR(200),IndexName VARCHAR(250),RecordCount BIGINT,	TotalAccesses BIGINT,TotalReads BIGINT)

SET @fillfactor = 100 --default is 0 which is same as 100; no space left on pages

--if want to use only the current database and comment where clase
set @DatabaseName = (select db_name())

insert into @IndexEvalTable (DatabaseName, DatabaseTable)
--select tables that may have problems for eval
SELECT [DBName],[TableName] as TableName
 FROM [DBAWORK].[dbo].[vw_Indexes_W_Free_Space_To_Rebuild]
  where Date > getdate()-6.9
  Union
  SELECT  [DBName],[TableName]  as TableName
 FROM [DBAWORK].[dbo].[vw_Top_Used_Tables_Fragmented]
  Union
  SELECT [DBName],[TableName]  as TableName
FROM [DBAWORK].[dbo].[vw_Out_Of_Date_Statistics_Top_Tables]
  Union
select DBName, TableName
from (SELECT TOP 100 [DBName]
      ,[TableName]
  FROM [DBAWORK].[dbo].[vw_Most_Used_Table_W_Row_Count]
--  where DBName = @DatabaseName
  order by TotalReads DESC) Z
  Union
  select DBName, TableName
from (SELECT TOP 100 [DBName]
      ,[TableName]
  FROM [DBAWORK].[dbo].[vw_Most_Used_Table_W_Row_Count]
  order by ReadScans DESC) Y

--specific indexes
insert into @IndexEvalTable2 (DatabaseName,DatabaseTable,IndexName)
Select [DB_Name],[Table_Name],[Index_Name]
  from 
(SELECT TOP 50 [DB_Name]
      ,[Table_Name]
      ,[Index_Name]
  FROM [DBAWORK].[dbo].[tb_Index_Usage_History]
  where Date > getdate()-6.9
  order by [user_seeks]+[user_scans]+[user_lookups]+[user_updates] DESC) Q
  Union
  SELECT [DBName],[TableName],[IndexName]
  FROM [DBAWORK].[dbo].[vw_Indexes_W_Free_Space_To_Rebuild]
  where Date > getdate()-6.9
  
 --update the table object id
 SET @RowCount = (SELECT COUNT(ID) FROM @IndexEvalTable) 
 
	--update TotalAccesses and TotalReads from 
update @IndexEvalTable
	set F.TotalAccesses = A.TotalAccesses, F.TotalReads = A.TotalReads
	from @IndexEvalTable F
	inner join (SELECT [DatabaseName] ,[TableName]  ,[TotalAccesses],[TotalReads] FROM [DBAWORK].[dbo].[tb_Most_Used_Table_History] where Date > getdate()-6.9) A
	on A.DatabaseName = F.DatabaseName and A.TableName = F.DatabaseTable

update @IndexEvalTable2
	set F.TotalAccesses = A.TotalAccesses, F.TotalReads = A.TotalReads
	from @IndexEvalTable2 F
	inner join (SELECT [DatabaseName] ,[TableName]  ,[TotalAccesses],[TotalReads] FROM [DBAWORK].[dbo].[tb_Most_Used_Table_History] where Date > getdate()-6.9) A
	on A.DatabaseName = F.DatabaseName and A.TableName = F.DatabaseTable

--update record count
 update @IndexEvalTable
	set F.RecordCount = A.[RowCount]
	from @IndexEvalTable F
	inner join (SELECT [DatabaseName] ,[TableName]  ,[RowCount] FROM [DBAWORK].[dbo].[tb_Table_Rows] where Date > getdate()-6.9) A
	on A.DatabaseName = F.DatabaseName and A.TableName = F.DatabaseTable

	 update @IndexEvalTable2
	set F.RecordCount = A.[RowCount]
	from @IndexEvalTable2 F
	inner join (SELECT [DatabaseName] ,[TableName]  ,[RowCount] FROM [DBAWORK].[dbo].[tb_Table_Rows] where Date > getdate()-6.9) A
	on A.DatabaseName = F.DatabaseName and A.TableName = F.DatabaseTable

  delete @IndexEvalTable where RecordCount > @RecordCount

--Prepare the Query to REBUILD the Indexes
SET @tsql = ''

if @Online = 1
SELECT @tsql = 
  STUFF(( SELECT DISTINCT 
		   ';' + 'EXECUTE [master].[dbo].[IndexOptimize] @Databases = [' + FI.DatabaseName + '], @Indexes = ''' + FI.DatabaseName + '.dbo.' + FI.DatabaseTable + ''',@PageCountLevel=8,@TimeLimit = 900, @MaxDOP = ''' + @MaxDOP + ''',@FragmentationMedium = ''INDEX_REBUILD_ONLINE,INDEX_REORGANIZE'', @FragmentationHigh = ''INDEX_REBUILD_ONLINE,INDEX_REORGANIZE'',@UpdateStatistics = ''ALL'', @OnlyModifiedStatistics = ''Y'', @LogToTable = ''Y'''
           FROM 
           @IndexEvalTable FI
	where FI.RecordCount < @RecordCount
          FOR XML PATH('')), 1,1,'')
else
SELECT @tsql = 
  STUFF(( SELECT DISTINCT 
		   ';' + 'EXECUTE [master].[dbo].[IndexOptimize] @Databases = [' + FI.DatabaseName + '], @Indexes = ''' + FI.DatabaseName + '.dbo.' + FI.DatabaseTable + ''',@PageCountLevel=8,@TimeLimit = 900, @MaxDOP = ''' + @MaxDOP + ''',@FragmentationMedium = ''INDEX_REBUILD_OFFLINE,INDEX_REORGANIZE'', @FragmentationHigh = ''INDEX_REBUILD_OFFLINE,INDEX_REORGANIZE'',@UpdateStatistics = ''ALL'', @OnlyModifiedStatistics = ''Y'', @LogToTable = ''Y'''
           FROM 
           @IndexEvalTable FI
	where FI.RecordCount < @RecordCount
          FOR XML PATH('')), 1,1,'')


SELECT @tsql
PRINT 'REBUILD Tables START'
print @tsql
EXEC sp_executesql @tsql
PRINT 'REBUILD Tables END'

--prep for index only rebuilds
SET @tsql = ''

if @Online = 1
SELECT @tsql = 
  STUFF(( SELECT DISTINCT 
		   ';' + 'EXECUTE [master].[dbo].[IndexOptimize] @Databases = [' + FI.DatabaseName + '], @Indexes = ''' + FI.DatabaseName + '.dbo.' + FI.DatabaseTable + '.[' + FI.IndexName + ']' +  ''',@PageCountLevel=8,@TimeLimit = 900, @MaxDOP = ''' + @MaxDOP + ''',@FragmentationMedium = ''INDEX_REBUILD_ONLINE,INDEX_REORGANIZE'', @FragmentationHigh = ''INDEX_REBUILD_ONLINE,INDEX_REORGANIZE'', @LogToTable = ''Y'''
          FROM 
           @IndexEvalTable2 FI
		   left outer join @IndexEvalTable T on FI.DatabaseName = T.DatabaseName and FI.DatabaseTable = T.DatabaseTable
			where T.DatabaseName is  null
          and FI.RecordCount < @IndexRecordCount 
          FOR XML PATH('')), 1,1,'')
else
SELECT @tsql = 
  STUFF(( SELECT DISTINCT 
		   ';' + 'EXECUTE [master].[dbo].[IndexOptimize] @Databases = [' + FI.DatabaseName + '], @Indexes = ''' + FI.DatabaseName + '.dbo.' + FI.DatabaseTable + '.[' + FI.IndexName + ']' +  ''',@PageCountLevel=8,@TimeLimit = 900, @MaxDOP = ''' + @MaxDOP + ''',@FragmentationMedium = ''INDEX_REBUILD_OFFLINE,INDEX_REORGANIZE'', @FragmentationHigh = ''INDEX_REBUILD_OFFLINE,INDEX_REORGANIZE'', @LogToTable = ''Y'''
          FROM 
           @IndexEvalTable2 FI
		   left outer join @IndexEvalTable T on FI.DatabaseName = T.DatabaseName and FI.DatabaseTable = T.DatabaseTable
			where T.DatabaseName is  null
          and FI.RecordCount < @IndexRecordCount 
          FOR XML PATH('')), 1,1,'')

SELECT @tsql
PRINT 'REBUILD Indexes START'
print @tsql
EXEC sp_executesql @tsql
PRINT 'REBUILD Indexes END'

GO


--bp_Stat_Rebuild_Targetted - needs to be added to each DB want to use in
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[bp_Stat_Rebuild_Targeted] @PercentModified int, @RowCount BIGINT, @RowCountThreshold INT
AS

--needs to be in each individual database to run against
--built by Todd Palecek to rebuild targetted table stats
--exec bp_Stat_Rebuild_Targetted 4, 5000000, 200000

declare @tsqlStatement nvarchar(max)

declare @Rebuilds Table 
( RebuildState nvarchar(500))

--declare @PercentModified int,
	--	@RowCount bigint,
--		@RowCountThreshold int

IF OBJECT_ID('tempdb..#tmpStatsRebuild', 'U') IS NOT NULL 
DROP TABLE tempdb..#tmpStatsRebuild;

--set @PercentModified = 2
--set @RowCount =24000000
--set @RowCountThreshold = 100000

--print @RowCount
--print @RowCountThreshold

select distinct 
I.*, R.[RowCount], U.[TotalAccesses],U.[TotalReads], ((cast(I.rowmodctr as bigint)*100)/cast(R.[RowCount] as bigint)) as 'PercentModified', 
'UPDATE STATISTICS [' + Table_Name + '](' + Index_Name + ') WITH FULLSCAN' AS RebuildState,
'ALTER INDEX ['+  Index_Name + '] ON [' + Table_Name + '] REBUILD with (ONLINE = ON,maxdop=8)' as IndexRebuild 
into #tmpStatsRebuild
from DBAWORK..tb_Table_Rows R 
inner join (
SELECT (SELECT DB_NAME()) as Database_Name, OBJECT_NAME(id) as 'Table_Name',name as 'Index_Name',STATS_DATE(id, indid) LastUpdateDate ,rowmodctr
FROM sys.sysindexes
where rowmodctr > 0
)I on R.TableName = I.Table_Name and R.DatabaseName = I.Database_Name
inner join [DBAWORK].[dbo].[tb_Most_Used_Table_History] U on U.DatabaseName = R.DatabaseName and U.TableName = R.TableName
where R.Date > getdate()-6.9 and U.Date>getdate()-6.9
and R.[RowCount] > 1
and left(I.Index_Name,1) != '_'  --include if only want index stats for index rebuilds
--and I.rowmodctr > 100
order by R.[RowCount] ASC

insert into @Rebuilds 
select RebuildState from #tmpStatsRebuild where PercentModified > @PercentModified and [RowCount] < @RowCount 
--added 2/16/17
union
select RebuildState from #tmpStatsRebuild where [rowmodctr] > @RowCountThreshold and [RowCount] < @RowCount 

--select * from #tmpStatsRebuild 
--select @RowCountThreshold

--select * from @Rebuilds order by RebuildState;

select @tsqlStatement = stuff((select ';' + RebuildState from @Rebuilds FOR XML PATH('')), 1,1,'')

print @tsqlStatement

EXEC sp_executesql @tsqlStatement

drop table #tmpStatsRebuild

GO




 
--create the jobs
USE [msdb]
GO

DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

--category
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Perf Monitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Perf Monitor'
END

DECLARE @jobId binary(16)

SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE (name = N'DBAWORK - Performance Monitoring')

IF (@jobId IS NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Performance Monitoring', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'execute package of performance measures to track history', 
		@category_name=N'Perf Monitor', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'bp_index_frag_history', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec bp_index_frag_history', 
		@database_name=N'DBAWORK', 
		@flags=0
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Weekly', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=32, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20150716, 
		@active_end_date=99991231, 
		@active_start_time=41500, 
		@active_end_time=235959
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
END
GO




DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

DECLARE @jobId BINARY(16)
SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE (name = N'DBAWORK - Lock Capture')

IF (@jobId IS NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Lock Capture', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name='Perf Monitor', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Lock capture', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'CREATE TABLE #LockHistory(
	[spid] [int] NULL,
	[dbid] [int] NULL,
	[objId] [int] NULL,
	[indId] [int] NULL,
	[Type] [char](4) NULL,
	[resource] [nchar](32) NULL,
	[Mode] [char](8) NULL,
	[status] [char](6) NULL
) ON [PRIMARY]

insert into #LockHistory
			exec sp_lock

insert into DBAWORK..tb_lock_history
select L.*, S.blocking_session_id, S.text, D.host_name,D.program_name,D.login_name, D.login_time,getdate() 
from #LockHistory L
left outer join (SELECT  blocking_session_id,text,session_id
            FROM    sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(sql_handle)) S on L.spid = S.session_id
left outer join sys.dm_exec_sessions D on D.session_id = L.spid

drop table #LockHistory

/*
SELECT 
      object_name([objId]) ObjectName
	  ,count(objId)
    ,count(blocking_session_id)
  FROM [DBAWORK].[dbo].[tb_lock_history] L
  LEFT OUTER JOIN sys.indexes AS i ON i.object_id = L.objId AND i.index_id = L.indId
  where object_name([objId]) not like ''change_tracking%''  and db_name([dbid]) != ''tempdb'' 
  group by objId
  order by count(objId) DESC
*/', 
		@database_name=N'DBAWORK', 
		@flags=0
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'On Demand', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=5, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20171115, 
		@active_end_date=20171115, 
		@active_start_time=34500, 
		@active_end_time=63059 
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
END
GO


USE [msdb]
GO

DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

--category
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Perf Monitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Perf Monitor'
END

--DECLARE @jobId binary(16)
--SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE (name = N'DBAWORK - SP Slow Check')
--IF (@jobId IS NOT NULL)
--BEGIN
--    EXEC msdb.dbo.sp_delete_job @jobId
--END
--GO


DECLARE @jobId binary(16)

SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE (name = N'DBAWORK - SP Slow Check')

IF (@jobId IS NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - SP Slow Check', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Stored Procs running slower than average', 
		@category_name=N'Perf Monitor', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'SP Check', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec [DBAWORK].[dbo].[bp_long_run_SP]', 
		@database_name=N'DBAWORK', 
		@flags=0
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Hourly', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=30, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20171004, 
		@active_end_date=99991231, 
		@active_start_time=300, 
		@active_end_time=235959
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(Local)'
END
GO


--create job for CPU 
USE [msdb]
GO

DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

--category
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Perf Monitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Perf Monitor'
END

DECLARE @jobId binary(16)
SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE (name = N'DBAWORK - Performance Monitoring CPU')

IF (@jobId IS NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Performance Monitoring CPU', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'monitor cpu utilization at 1 minute intervals', 
		@category_name=N'Perf Monitor', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'CPU Monitor', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec bp_cpu_utilization', 
		@database_name=N'DBAWORK', 
		@flags=0
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'2 Hours', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=2, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20150731, 
		@active_end_date=99991231, 
		@active_start_time=3500, 
		@active_end_time=3459
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
END
GO


USE [msdb]
GO

DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

--category
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Perf Monitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Perf Monitor'
END

DECLARE @jobId binary(16)

SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE (name = N'DBAWORK - Targeted Index and Stats')
IF (@jobId IS NULL)
BEGIN
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Targeted Index and Stats', 
		@enabled=0, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'targeted stats update because Invoicing running slow sometimes', 
		@category_name=N'Perf Monitor', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Rebuild Indexes Smaller Tables', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec dbawork..bp_Index_Rebuild_Targeted 2, 1700000, 3000000

--maxdop, record count, index record count', 
		@database_name=N'DBAWORK', 
		@flags=0
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Update Stats', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec bp_Stat_Rebuild_Targeted 2, 45000000, 90000

--percent modified, table row count, row count modified as override for precent modified', 
		@database_name=N'DBAWORK', 
		@flags=0
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Nightly', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=126, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20170216, 
		@active_end_date=99991231, 
		@active_start_time=233100, 
		@active_end_time=235959
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
END
GO