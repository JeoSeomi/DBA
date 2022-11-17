/*#############################################################

�ܼ� ��ũ��Ʈ ����(��µ� ��ũ��Ʈ�� �����ϴ� ����)
exec [spCopyAccount] @bintSrcAccountUID =2082

--���̺�QA����(Linked ������ ������ ��� ����� �Ϸù�ȣ�� ���缭 ����ϴ� ����)
exec [spCopyAccount] @bintSrcAccountUID =�ҽ�AUID, @varLinkedServer = 'LINK_GDB_01'

--���� ��񿡼� ����� �ƴ� �ٷ� �����ϴ� ����
exec [spCopyAccount] @bintSrcAccountUID =�ҽ�AUID
	, @nvcReplacePID  =  N'������PID'
	, @nvcReplaceAccountName = N'���������г���'
	, @IsExecute = 1

###############################################################*/

CREATE procedure [dbo].[spCopyAccount]
	@varLinkedServer varchar(24) = null							-- Linked Server
	--, @nvcSrcPID nvarchar(64)									-- ���� PID
	, @bintSrcAccountUID bigint									-- ���� AccountUID
	, @nvcReplacePID nvarchar(64) =  null						-- ������ PID	
	, @nvcReplaceAccountName nvarchar(16) = null				-- ������ �г���
	, @varTargetDatabase varchar(64) ='GameDB'					-- ��� �����ͺ��̽�
	, @varRemoteDatabase varchar(64) ='GameDB'					-- �ҽ� �����ͺ��̽�
	, @IsExecute bit = 0
	, @binNewAccountUID bigint = 0 output
	, @nvcNewPID nvarchar(64) = null output
with execute as caller
as

set transaction isolation level read uncommitted;
set nocount on

/* ------------------------------------------------------------------
	PID üũ
------------------------------------------------------------------ */
if len(@nvcReplacePID) < 2
begin
	return 0;
end


declare @inyAccountType int = 1;
declare @intCopyCount int = 1
declare @isInfo bit = 0;
		
declare @nvcNormalTableList nvarchar(max) = '';
declare @nvcTableName nvarchar(64) = '', @IsTable bit = 0;
declare @SearchCondition nvarchar(1024) = NULL;
declare @ReplaceColumn1 nvarchar(261) = NULL
declare @ReplaceValue1 nvarchar(261) = NULL;
declare @ReplaceColumn2 nvarchar(261) = NULL
declare @ReplaceValue2 nvarchar(261) = NULL;
declare @ReplaceColumn3 nvarchar(261) = NULL
declare @ReplaceValue3 nvarchar(261) = NULL;
declare @ReplaceColumn4 nvarchar(261) = NULL
declare @ReplaceValue4 nvarchar(261) = NULL;
declare @nvcQueryStr nvarchar(max)=''
declare @nvcParmDefinition nvarchar(500);

--------------------------------------------------------------------------
-- �߿��� �ɼ�
--------------------------------------------------------------------------
declare @PrintGeneratedCode bit = 1											--1 : print, 0 : select
declare @IsLinedServer bit = iif(@varLinkedServer is null, 0, 1);			--linked server ����

if @IsExecute = 1 and @varLinkedServer is not null
begin
	print N'���� ������ �ٷ� INSERT�� �ȵ˴ϴ�.\n��µǴ� ��ũ��Ʈ�� �����ؼ� �����ϼ���!'
	return 0;
end

--�ٷ� INSERT
if @IsExecute = 1
begin
	set @PrintGeneratedCode = 0;
end

----����--
-- ������ ����ϸ� �ȵȴ�..(�ٷ� ���� ���� �ɼ�)
-- �Ʒ� ������ �ּ� Ǯ�� �ٷ� ��� ����˴ϴ�(��, ������ �ȵ˴ϴ�....)
--select @PrintGeneratedCode = 0, @IsExecute = 1, @IsLinedServer = 1;


--------------------------------------------------------------------------
-- �⺻ ����
--------------------------------------------------------------------------
--declare @varLinkedServer varchar(24) ='192.168.100.130,1433'		--�ҽ� Linked Server
--declare @varLinkedServer varchar(24) ='192.168.100.163,30323'		--�ҽ� Linked Server
--declare @varTargetDatabase varchar(64) ='GameDB_DesignTest05',
--declare @varTargetDatabase varchar(64) ='GameDB',					--��� �����ͺ��̽�
--		@varRemoteDatabase varchar(64) ='GameDB';					--�ҽ� �����ͺ��̽�
		
--------------------------------------------------------------------------
-- ******** AccountUID�� ���� �˴ϴ�. ********
--------------------------------------------------------------------------
declare @bigSrcAccountUID bigint = 0						--�ҽ� AccountUID
declare @bigNewAccountUID bigint = 0;
--------------------------------------------------------------------------


/* ------------------------------------------------------------------
	���� ��� �Ǽ�
------------------------------------------------------------------ */
declare @intTargetCount int = 0;
--set @nvcQueryStr = concat('select @intTargetCount = count(*), @bigSrcAccountUID = AccountUID from '
--	, iif(@varLinkedServer is null,'', '['+ @varLinkedServer + '].')
--	, ' ['+ @varRemoteDatabase +'].dbo.Account with (nolock) where PID like '
--	, 'N', '''', @nvcSrcPID, '''', ' group by AccountUID;');
set @nvcQueryStr = concat('select @intTargetCount = count(*), @bigSrcAccountUID = AccountUID from '
	, iif(@varLinkedServer is null,'', '['+ @varLinkedServer + '].')
	, ' ['+ @varRemoteDatabase +'].dbo.Account with (nolock) where AccountUID = '
	, 'N', '''', @bintSrcAccountUID, '''', ' group by AccountUID;');
set @nvcParmDefinition = N'@intTargetCount int output, @bigSrcAccountUID bigint output';
--print @nvcQueryStr
exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
	@intTargetCount		= @intTargetCount output,
	@bigSrcAccountUID	= @bigSrcAccountUID output;

if @intTargetCount =0
begin
	print N'���� ��� PID�� �����ϴ�'
	return 0;
end

/* ------------------------------------------------------------------
PID, AccountName ó��
------------------------------------------------------------------ */
if @nvcReplacePID is null
begin
	set @nvcReplacePID = CONVERT(varchar(20),CRYPT_GEN_RANDOM(20),2);
end
if @nvcReplaceAccountName is null
begin
	set @nvcReplaceAccountName = N'��'+ CONCAT(LEFT(@nvcReplacePID, 5),format(getdate(),'ddHHmmss'));
end


/* ------------------------------------------------------------------
AccountUID ó��
------------------------------------------------------------------ */
set @bigNewAccountUID = 0;
set @SearchCondition = 'AccountUID = ''' + cast(@bigSrcAccountUID as varchar(64))+ '''';
set @nvcQueryStr = 'select @bigNewAccountUID = next value for ['+ @varTargetDatabase +'].dbo.sqAccountUID_9;';
set @nvcParmDefinition = N'@bigNewAccountUID bigint output';
exec sp_executesql @nvcQueryStr, @nvcParmDefinition,  
                      @bigNewAccountUID = @bigNewAccountUID output;

set @ReplaceValue1  = N'''' + convert(nvarchar(26), @bigNewAccountUID) + '''';
set @ReplaceValue2  = N'''' + @nvcReplacePID + '''';
set @ReplaceValue3  = N'''' + @nvcReplaceAccountName + '''';
set @ReplaceValue4  = '''' + convert(nvarchar(26), @inyAccountType) + '''';		


print 'use '+ @varTargetDatabase
print 'go'
print '-----------------------------------------------'
print '--new Accountuid : ' + cast(@bigNewAccountUID as varchar(64));
print '--new PID		: ' + @ReplaceValue2;
print '--new AccountName: ' + @ReplaceValue3;
print '---' + CONVERT(CHAR(23), getdate(), 21)
print '-----------------------------------------------'
				
set @binNewAccountUID = @binNewAccountUID;
set @nvcNewPID = @ReplaceValue2;
  

	/* ------------------------------------------------------------------
	AccountUID ����
	------------------------------------------------------------------ */
	set @nvcQueryStr = N'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert 		
		@ObjectName= ''Account''
	,	@SearchCondition= @SearchCondition
	,	@ReplaceColumn1  = ''AccountUID''
	,	@ReplaceValue1 = @ReplaceValue1
	,	@ReplaceColumn2 = ''PID''
	,	@ReplaceValue2 = @ReplaceValue2
	,	@ReplaceColumn3 = ''AccountName''
	,	@ReplaceValue3 = @ReplaceValue3
	,	@ReplaceColumn4 = ''AccountType''
	,	@ReplaceValue4 = @ReplaceValue4
	,	@PrintGeneratedCode = @PrintGeneratedCode
	,	@IsExecute =@IsExecute
	,	@IsLinedServer =@IsLinedServer
	,	@ExecuteDatabase = @varTargetDatabase'
	
	set @nvcParmDefinition = N'@SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
							, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit
							, @varTargetDatabase varchar(64), @ReplaceValue4 nvarchar(261)';
	exec sp_executesql @nvcQueryStr, @nvcParmDefinition,  
	                      @SearchCondition = @SearchCondition,
						  @ReplaceValue1 = @ReplaceValue1,
						  @ReplaceValue2 = @ReplaceValue2,
						  @ReplaceValue3 = @ReplaceValue3,							  
						  @ReplaceValue4 = @ReplaceValue4,  
						  @PrintGeneratedCode = @PrintGeneratedCode,
						  @IsExecute = @IsExecute,
						  @IsLinedServer = @IsLinedServer,
						  @varTargetDatabase = @varTargetDatabase;						  
	

		------------------------------------------------------------------------------------------------------------------------

		
		/* ------------------------------------------------------------------
		AccountUID ���� ���̺� ó��
		------------------------------------------------------------------ */
		set @nvcNormalTableList = 'AccountArea,AccountBuyLimit,AccountContentsCount,AccountDetail,AccountFixedGacha,AccountFixedGachaCount,AccountFreeGacha
		,InfiniteMazeSequencePlay,InfiniteMazeHistoryReward,ArenaSeason,ArenaPromotion,ArenaHallOfFame
		,AccountGachaBonusCorrection,AccountGoods,AccountHallObject,AccountOption
		,AccountProfileIcon,AccountPushPresent,AccountGrowthPackage,AccountSequenceReward,AccountRetainInfo
		,AccountStoreInfo,AccountTicket,AccountTutorialClearInfo,AIAccount,AIUserSegment,Arena
		,ArenaDeckEnchant,ArenaSelectedEnchantID,CharacterUnLock,DungeonAutoClearInfo,DungeonPlayInfo
		,OpenArea,PresentBox,PresentBoxGuild,PresentBoxInApp,PresentBoxNotice,AccountReddotVariable
		,QuestProgress,QuestWeapon,Quest,QuestGranWeapon,AccountTrait,InteractionCount
		,AccountEventGachaBox,AccountEventCount
		,AccountLevelUpReward,CharacterGoodWillReward,AccountContentsCountWhole		
		,CharacterGoodWillInfo,Costume,AccountEventCount,OperationEvent,MonsterCollection
		,AccountTitleName,InfiniteMazeSkillReward,AccountGachaMileage,AccountItemCollectionProgressRewardInfo
		,AccountPopUpEvent,InfiniteMazePathTile,AccountCollectionGroupInfo,ItemGoodWillDetail,ItemGoodWill,InfiniteMazeCharacterInfo
		,InfiniteMazeTile,AccountCalendar,AccountInGameShopInfo,InfiniteMazeNpcInfo,QuestTitleName,AccountMarathonEvent,AccountInfiniteMazeProgress
		,AccountBlessing,AccountCoupon,AccountDeviceOsReward,AccountSkillInfo,AccountSkillPresetInfo,QuestResetInfo
		,InfiniteMazeVerifiedPathTile,AccountEventGranFestival,WebEventPresent,AccountSeasonPassReward,AccountGiftReceiveInfo
		,AccountMoonStone,AccountPresetOption,AccountSoulMastery,AccountKeystoneTrait
		,AccountCompetition,AccountCompetitionDeck,AccountSnsReward,InfiniteMazeProgressInfo,AccountMembershipInfo,AccountCharacterDeck
		,OperationEventSchedule,AccountResetData,AccountOptionJson,AccountMascot,AccountGuardianTraitReward,AccountGuardianTrait
        ,AccountGuardianRecruitGift,AccountGuardianRecruit,AccountGuardian,AccountEventGachaMissionInfo,OperationEventGradeReward,AccountWishList,AccountOperationEventInfo
        ,AccountMissionSelectEvent,AccountEventPickUpAfter,AccountAutoSellInfo,AccountTreasureHunt,AccountEnhanceTrait'		--Ư��ó��(update)
		+ ',ProgressReward'	-- ������ ����� ������ ����
		--AccountPurchase(pass),AccountPurchaseHistory,AccountGiftInfo
		
		
		declare ColumnCursor cursor local fast_forward for
			select replace(
							replace(
									replace(
											replace(value, char(13), '')
											, char(10), '')
									,'	','')
							,' ','')
			from string_split(@nvcNormalTableList, ',')  
			where rtrim(rtrim(value)) <> ''
			for read only;
		
		open ColumnCursor;
		fetch next from ColumnCursor into @nvcTableName;
		
		while @@fetch_status = 0
		begin
			if @isInfo = 1
			begin
				print '-----------------------------------------------'
				print '--request table name : ' + @nvcTableName;
				print '-----------------------------------------------'
			end
			
			set @nvcTableName = replace(
										replace(
												replace(
														replace(@nvcTableName, char(13), '')
														, char(10), '')
												,'	','')
										,' ','')


			set @nvcQueryStr = 'select @IsTable = count(1) from ['+ @varTargetDatabase + '].sys.tables where name =@nvcTableName';
			set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @IsTable bit output';
			exec sp_executesql @nvcQueryStr, @nvcParmDefinition,  
								@nvcTableName = @nvcTableName,
								@IsTable = @IsTable output;
			
			if @IsTable = 1
			begin
				
				if @nvcTableName ='Quest'
				begin
					set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert
						@ObjectName= @nvcTableName
					,	@SearchCondition= @SearchCondition
					,	@ReplaceColumn1  = ''AccountUID''
					,	@ReplaceValue1 = @ReplaceValue1	
					,	@ReplaceColumn2 = ''UniqueID''
					,	@ReplaceValue2 = ''CAST(NEXT VALUE FOR [dbo].[sqQuestUID] as NVARCHAR(30))''
					,	@PrintGeneratedCode = @PrintGeneratedCode
					,	@IsExecute =@IsExecute
					,	@IsLinedServer =@IsLinedServer
					,	@ExecuteDatabase = @varTargetDatabase'
					
					set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
											, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
					exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
											@nvcTableName = @nvcTableName,
											@SearchCondition = @SearchCondition,
											@ReplaceValue1 = @ReplaceValue1,
											@ReplaceValue2 = @ReplaceValue2,
											@ReplaceValue3 = @ReplaceValue3,
											@PrintGeneratedCode = @PrintGeneratedCode,
											@IsExecute = @IsExecute,
											@IsLinedServer = @IsLinedServer,
											@varTargetDatabase = @varTargetDatabase;
				end
				else if @nvcTableName in ('AccountCollectionGroupInfo','AccountContentsCount','AccountTrait','InfiniteMazeVerifiedPathTile','Costume','AccountInGameShopInfo','AccountPushPresent','DungeonPlayInfo','PresentBoxNotice', 'ItemGoodWillDetail')
				begin
					set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert
						@ObjectName= @nvcTableName
					,	@SearchCondition= @SearchCondition
					,	@ReplaceColumn1  = ''AccountUID''
					,	@ReplaceValue1 = @ReplaceValue1	
					,	@PrintGeneratedCode = @PrintGeneratedCode
					,	@IsExecute =@IsExecute
					,	@IsLinedServer =@IsLinedServer
					,	@ExecuteDatabase = @varTargetDatabase
					,	@GenerateSingleInsertPerRow=1'
					
					set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
											, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
					exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
											@nvcTableName = @nvcTableName,
											@SearchCondition = @SearchCondition,
											@ReplaceValue1 = @ReplaceValue1,
											@ReplaceValue2 = @ReplaceValue2,
											@ReplaceValue3 = @ReplaceValue3,
											@PrintGeneratedCode = @PrintGeneratedCode,
											@IsExecute = @IsExecute,
											@IsLinedServer = @IsLinedServer,
											@varTargetDatabase = @varTargetDatabase;
				end
				else
				begin
					if @nvcTableName in ('PresentBox','PresentBoxGuild','PresentBoxInApp')
					begin
						set @SearchCondition = '[Status] = 1 and AccountUID = ''' + cast(@bigSrcAccountUID as varchar(64))+ '''';
					end
					if @nvcTableName in ('InfiniteMazeTile')
					begin
						set @SearchCondition = '[State] = 1 and AccountUID = ''' + cast(@bigSrcAccountUID as varchar(64))+ '''';
					end
					if @nvcTableName in ('OperationEvent')
					begin
						set @SearchCondition = '[RemoveType] = 0 and AccountUID = ''' + cast(@bigSrcAccountUID as varchar(64))+ '''';
					end					

					set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert
						@ObjectName= @nvcTableName
					,	@SearchCondition= @SearchCondition
					,	@ReplaceColumn1  = ''AccountUID''
					,	@ReplaceValue1 = @ReplaceValue1	
					,	@PrintGeneratedCode = @PrintGeneratedCode
					,	@IsExecute =@IsExecute
					,	@IsLinedServer =@IsLinedServer
					,	@ExecuteDatabase = @varTargetDatabase'
					
					set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
											, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
					exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
											@nvcTableName = @nvcTableName,
											@SearchCondition = @SearchCondition,
											@ReplaceValue1 = @ReplaceValue1,
											@ReplaceValue2 = @ReplaceValue2,
											@ReplaceValue3 = @ReplaceValue3,
											@PrintGeneratedCode = @PrintGeneratedCode,
											@IsExecute = @IsExecute,
											@IsLinedServer = @IsLinedServer,
											@varTargetDatabase = @varTargetDatabase;
				end
				set @SearchCondition = 'AccountUID = ''' + cast(@bigSrcAccountUID as varchar(64))+ '''';
			end
			else
			begin
				print '---------------------------------------------------------'
				print '-- ' + @nvcTableName + N' ���̺��� �����''' 
				print '---------------------------------------------------------'
			end
		
		  fetch next from ColumnCursor into @nvcTableName;
		end
		
		close ColumnCursor;
		deallocate ColumnCursor;
		
		
		

		/* ------------------------------------------------------------------
		AccountUID + CharacterUID = 0 ó��
		------------------------------------------------------------------ */
		if @isInfo = 1
		begin
			print N'--###########################################################################'
			print N'--(AccountUID + CharacterUID = 0) ó��'
			print N'--###########################################################################'
		end

		set @nvcNormalTableList = 'AccountContentsUnlock,AccountStatInfo'			
		set @SearchCondition = 'AccountUID = ''' + cast(@bigSrcAccountUID as varchar(64))+ ''' and CharacterUID = ''0''';
		
		declare ColumnCursor cursor local fast_forward for
			select replace(
							replace(
									replace(
											replace(value, char(13), '')
											, char(10), '')
									,'	','')
							,' ','')
			from string_split(@nvcNormalTableList, ',')  
			where rtrim(rtrim(value)) <> ''
			for read only;
		
		open ColumnCursor;
		fetch next from ColumnCursor into @nvcTableName;
		
		while @@fetch_status = 0
		begin
			if @isInfo = 1
			begin
				print '-----------------------------------------------'
				print '--request table name : ' + @nvcTableName;
				print '-----------------------------------------------'
			end
			
			set @nvcTableName = replace(
										replace(
												replace(
														replace(@nvcTableName, char(13), '')
														, char(10), '')
												,'	','')
										,' ','')
		
			set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert			
				@ObjectName= @nvcTableName
			,	@SearchCondition= @SearchCondition
			,	@ReplaceColumn1  = ''AccountUID''
			,	@ReplaceValue1 = @ReplaceValue1	
			,	@PrintGeneratedCode = @PrintGeneratedCode
			,	@IsExecute =@IsExecute
			,	@IsLinedServer =@IsLinedServer
			,	@ExecuteDatabase = @varTargetDatabase'
			
			set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
									, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
			exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
									@nvcTableName = @nvcTableName,
									@SearchCondition = @SearchCondition,
									@ReplaceValue1 = @ReplaceValue1,
									@ReplaceValue2 = @ReplaceValue2,
									@ReplaceValue3 = @ReplaceValue3,
									@PrintGeneratedCode = @PrintGeneratedCode,
									@IsExecute = @IsExecute,
									@IsLinedServer = @IsLinedServer,
									@varTargetDatabase = @varTargetDatabase;   
		
		  fetch next from ColumnCursor into @nvcTableName;
		end
		
		close ColumnCursor;
		deallocate ColumnCursor;


		if @isInfo = 1
		begin
			print N'--###########################################################################'
			print N'--ĳ���� ó��'
			print N'--###########################################################################'
		end
		
		if object_id('tempdb..#CharacterListTmp') is not null
			drop table #CharacterListTmp;
		
		create table #CharacterListTmp(
			Seq	int identity(1,1),
			AccountUID bigint not null,
			CharacterUID bigint not null,
			NewCharacterUID bigint not null default(0)
		)

		create clustered index tix_CharacterListTmp_010 on #CharacterListTmp(Seq);

		

		if @varLinkedServer is null
		begin
			set @nvcQueryStr= concat('select AccountUID, CharacterUID from [', @varRemoteDatabase, ']..[Character] with (nolock) where AccountUID = ',  cast(@bigSrcAccountUID as varchar(max)))
		end
		else
		begin
			set @nvcQueryStr= concat('select AccountUID, CharacterUID from openquery([', @varLinkedServer, '],''select AccountUID, CharacterUID from ['
				, @varRemoteDatabase, ']..[Character] with (nolock) where AccountUID = ', cast(@bigSrcAccountUID as varchar(max)), ''')')
		end		
		--print(@nvcQueryStr)
		insert into #CharacterListTmp(AccountUID, CharacterUID)
		exec (@nvcQueryStr)
		
						
		declare @intMaxSeq int = (select max(seq) from #CharacterListTmp)
		declare @bigOldCharacterUID bigint =0;
		declare @bigOldAccountUID bigint =0;
		declare @bigNewCharacterUID bigint =0;
		
		while @intMaxSeq >= 1
		begin
			--print @intMaxSeq
			select @bigOldCharacterUID = CharacterUID, @bigOldAccountUID = AccountUID from #CharacterListTmp where Seq = @intMaxSeq;
			--set @SearchCondition = ' AccountUID = ''' + cast(@bigSrcAccountUID as nvarchar(56)) + ''' and CharacterUID = ''' + cast(@bigOldCharacterUID as nvarchar(56)) + ''''
			set @SearchCondition = ' CharacterUID = ''' + cast(@bigOldCharacterUID as nvarchar(56)) + ''''
			set @nvcQueryStr = 'select @bigNewCharacterUID = next value for ['+ @varTargetDatabase +'].dbo.[sqCharacterUID];';
			set @nvcParmDefinition = N'@bigNewCharacterUID bigint output';
			exec sp_executesql @nvcQueryStr, @nvcParmDefinition,  
		                      @bigNewCharacterUID = @bigNewCharacterUID output;
			set @ReplaceValue2  = '''' + convert(nvarchar(26), @bigNewCharacterUID) + '''';
			
			if @isInfo = 1
			begin				   	 		
				print N'--###########################################################################'
				print N'-- ���� ĳ���� UID : ' + cast(@bigOldCharacterUID as nvarchar(56))
				print N'-- �ű� ĳ���� UID : ' + cast(@bigNewCharacterUID as nvarchar(56))
				print N'--###########################################################################'		
			end
			
			--�ű� ĳ���� ���� UPDATE
			update #CharacterListTmp set NewCharacterUID = @bigNewCharacterUID where Seq = @intMaxSeq;
			
			/* ------------------------------------------------------------------
			CharacterUID ���� ���̺� ó��
			------------------------------------------------------------------ */
			set @nvcNormalTableList = 'Character,AccountContentsUnlock,ItemCoolTime
		,InventoryCoolTime,CharacterEquipPreset,CharacterSkill,CharacterQuest,CharacterCostumeColor
		,AccountStatInfo,CharacterStatusEffect,CharacterDefensePreset,CharacterCostumePreset'
			-- preset ���� ���� �߰�
			SET @nvcNormalTableList += ',AccountCharacterDeckPreset,CharacterEquipPresetDetail,AccountCharacterPresetOption'		
			
			declare ColumnCursor cursor local fast_forward for
				select replace(
							replace(
									replace(
											replace(value, char(13), '')
											, char(10), '')
									,'	','')
							,' ','')
				from string_split(@nvcNormalTableList, ',')  
				where rtrim(rtrim(value)) <> ''
				for read only;
			
			open ColumnCursor;
			fetch next from ColumnCursor into @nvcTableName;
			
			while @@fetch_status = 0
			begin
				if @isInfo = 1
				begin
					print '-----------------------------------------------'
					print '--request table name : ' + @nvcTableName + '-- CharacterUID : ' + @SearchCondition ;
					print '-----------------------------------------------'
				end
				
				set @nvcTableName = replace(
										replace(
												replace(
														replace(@nvcTableName, char(13), '')
														, char(10), '')
												,'	','')
										,' ','')
				
				--print @nvcTableName
				--if @nvcTableName = 'CharacterCostumeColor'
				--	set @PrintGeneratedCode = 0
				set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert				
						@ObjectName= @nvcTableName
					,	@SearchCondition= @SearchCondition
					,	@ReplaceColumn1  = ''AccountUID''
					,	@ReplaceValue1 = @ReplaceValue1	
					,	@ReplaceColumn2 = ''CharacterUID''
					,	@ReplaceValue2 = @ReplaceValue2
					,	@PrintGeneratedCode = @PrintGeneratedCode
					,	@IsExecute =@IsExecute
					,	@IsLinedServer =@IsLinedServer
					,	@ExecuteDatabase = @varTargetDatabase
					,	@Debug = 0'
					
					set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
											, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
					
					if @nvcTableName in( N'Character', 'AccountContentsUnlock','ItemCoolTime','CharacterEquipPreset','CharacterQuest','CharacterCostumeColor','AccountStatInfo','CharacterStatusEffect','CharacterDefensePreset','CharacterCostumePreset'
										-- preset ���� �߰�
										,'AccountCharacterDeckPreset','CharacterEquipPresetDetail','AccountCharacterPresetOption')
					begin
						set @SearchCondition = @SearchCondition + ' and AccountUID = ''' + cast(@bigOldAccountUID as nvarchar(56)) + ''''
						--print @SearchCondition
						--print '-------------------------------------------------'
						--print @nvcQueryStr
						--print @SearchCondition
						--print @ReplaceValue1
						--print @ReplaceValue2
						--print @ReplaceValue3
						--print @PrintGeneratedCode
						--print @IsExecute
						--print @IsLinedServer
						--print @varTargetDatabase
						--print '-------------------------------------------------'
					end
					--print @nvcTableName
					exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
											@nvcTableName = @nvcTableName,
											@SearchCondition = @SearchCondition,
											@ReplaceValue1 = @ReplaceValue1,
											@ReplaceValue2 = @ReplaceValue2,
											@ReplaceValue3 = @ReplaceValue3,
											@PrintGeneratedCode = @PrintGeneratedCode,
											@IsExecute = @IsExecute,
											@IsLinedServer = @IsLinedServer,
											@varTargetDatabase = @varTargetDatabase;   
					
					set @SearchCondition = ' CharacterUID = ''' + cast(@bigOldCharacterUID as nvarchar(56)) + ''''
					
				
				----update ó���ؾ� �� ���̺�
					
			  fetch next from ColumnCursor into @nvcTableName;
			end
			
			close ColumnCursor;
			deallocate ColumnCursor;
			
			--------------------------------------------------------------------
			-- ĳ���� �÷��� ���� �� ó��
			--------------------------------------------------------------------
			if @IsExecute = 1
				begin
					--AccountCharacterDeck
					set @nvcQueryStr = 'update AccountCharacterDeck set CharacterUID1 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and CharacterUID1 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
					set @nvcQueryStr = 'update AccountCharacterDeck set CharacterUID2 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and CharacterUID2 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
					set @nvcQueryStr = 'update AccountCharacterDeck set CharacterUID3 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and CharacterUID3 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)		
					
					--Arena
					set @nvcQueryStr = 'update [dbo].[Arena] set [PvPCharacterUID1] = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and PvPCharacterUID1 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
					set @nvcQueryStr = 'update [dbo].[Arena] set [PvPCharacterUID2] = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and PvPCharacterUID2 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
					set @nvcQueryStr = 'update [dbo].[Arena] set [PvPCharacterUID3] = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and PvPCharacterUID3 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)

					set @nvcQueryStr = 'update [dbo].[Arena] set [DefenseCharacterUID1] = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and DefenseCharacterUID1 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
					set @nvcQueryStr = 'update [dbo].[Arena] set [DefenseCharacterUID2] = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and DefenseCharacterUID2 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
					set @nvcQueryStr = 'update [dbo].[Arena] set [DefenseCharacterUID3] = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and DefenseCharacterUID3 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)


				end
			else
				begin
					--AccountCharacterDeck
					print N'update ['+ @varTargetDatabase +'].dbo.AccountCharacterDeck set CharacterUID1 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and CharacterUID1 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					print N'update ['+ @varTargetDatabase +'].dbo.AccountCharacterDeck set CharacterUID2 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and CharacterUID2 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N'update ['+ @varTargetDatabase +'].dbo.AccountCharacterDeck set CharacterUID3 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and CharacterUID3 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N''
					--Arena
					print N'update ['+ @varTargetDatabase +'].dbo.Arena set PvPCharacterUID1 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and PvPCharacterUID1 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';' 
					print N'update ['+ @varTargetDatabase +'].dbo.Arena set PvPCharacterUID2 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and PvPCharacterUID2 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N'update ['+ @varTargetDatabase +'].dbo.Arena set PvPCharacterUID3 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and PvPCharacterUID3 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N'update ['+ @varTargetDatabase +'].dbo.Arena set DefenseCharacterUID1 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and DefenseCharacterUID1 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N'update ['+ @varTargetDatabase +'].dbo.Arena set DefenseCharacterUID2 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and DefenseCharacterUID2 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N'update ['+ @varTargetDatabase +'].dbo.Arena set DefenseCharacterUID3 = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and DefenseCharacterUID3 = ' + cast(@bigOldCharacterUID as varchar(max)) + ';'
					print N''
					
				end	
			
			set @intMaxSeq -= 1;
		end
		
		if @isInfo = 1
		begin
			print N'--###########################################################################'
			print N'-- Item ó��'
			print N'--###########################################################################'
		end
		
		if object_id('tempdb..#ItemListTmp') is not null
			drop table #ItemListTmp;
		
		create table #ItemListTmp(
			Seq	int identity(1,1),
			ItemUID bigint not null,
			EquipCharacterUID bigint null
		)

		create clustered index tix_ItemListTmp_010 on #ItemListTmp(Seq);
		
		--------------------------------------------------------------------------------
		--  ���� ItemUID 
		--------------------------------------------------------------------------------
		if @varLinkedServer is null
		begin
			set @nvcQueryStr= concat('select ItemUID from [', @varRemoteDatabase, ']..[Inventory] with (nolock) where [Status] = 1 and AccountUID = ', cast(@bigSrcAccountUID as varchar(max)))
			insert into #ItemListTmp(ItemUID)
			exec (@nvcQueryStr)

			--------------------------------------------------------------------------------
			--  ���� ItemUID 
			--------------------------------------------------------------------------------		
			set @nvcQueryStr= 	concat('
								update A
									set EquipCharacterUID = B.ItemUID
								from #ItemListTmp as A
									inner join (
											select distinct A.ItemUID
											from [', @varRemoteDatabase, ']..Inventory as A with (nolock)
												cross apply  (
													select AccountUID 
													From [', @varRemoteDatabase, ']..[CharacterEquipPreset] as B with (nolock) 
													where B.AccountUID = ', @bigSrcAccountUID ,' 
														and A.ItemUID in ( B.ItemUID_1, B.ItemUID_2, B.ItemUID_3, B.ItemUID_4, B.ItemUID_5, B.ItemUID_6, B.ItemUID_7, B.ItemUID_8, B.ItemUID_9, B.ItemUID_10
																			, B.ItemUID_11, B.ItemUID_12, B.ItemUID_13, B.ItemUID_14, B.ItemUID_15, B.ItemUID_16, B.ItemUID_17, B.ItemUID_18, B.ItemUID_19, B.ItemUID_20)
													) as B
											where A.AccountUID = ', @bigSrcAccountUID, ' and A.[Status] = 1
									) as B
											on B.ItemUID = A.ItemUID
								')
			exec (@nvcQueryStr)
		end
		else
		begin
			set @nvcQueryStr= concat('select ItemUID from openquery([', @varLinkedServer, '],''select ItemUID from ['
				, @varRemoteDatabase, ']..[Inventory] with (nolock) where [Status] = 1 and AccountUID = ', cast(@bigSrcAccountUID as varchar(max)), ''')')
			insert into #ItemListTmp(ItemUID)
			exec (@nvcQueryStr)
			--------------------------------------------------------------------------------
			--  ���� ItemUID 
			--------------------------------------------------------------------------------		
			set @nvcQueryStr= 	concat('
								update A
									set EquipCharacterUID = B.ItemUID
								from #ItemListTmp as A
									inner join (
											select *
											from openquery([', @varLinkedServer, '],', '''','
															select distinct A.ItemUID
															from [', @varRemoteDatabase, ']..Inventory as A with (nolock)
																cross apply  (
																	select AccountUID 
																	From [', @varRemoteDatabase, ']..[CharacterEquipPreset] as B with (nolock) 
																	where B.AccountUID = ', @bigSrcAccountUID ,' 
																		and A.ItemUID in ( B.ItemUID_1, B.ItemUID_2, B.ItemUID_3, B.ItemUID_4, B.ItemUID_5, B.ItemUID_6, B.ItemUID_7, B.ItemUID_8, B.ItemUID_9, B.ItemUID_10
																							, B.ItemUID_11, B.ItemUID_12, B.ItemUID_13, B.ItemUID_14, B.ItemUID_15, B.ItemUID_16, B.ItemUID_17, B.ItemUID_18, B.ItemUID_19, B.ItemUID_20)
																	) as B
															where A.AccountUID = ', @bigSrcAccountUID, ' and A.[Status] = 1
											', '''',') 

									) as B
											on B.ItemUID = A.ItemUID
								')
			--print @nvcQueryStr
			exec (@nvcQueryStr)
		end		
		

		declare @intItemMaxSeq int = (select max(seq) from #ItemListTmp)
		declare @bigOldItemUID bigint =0;
		declare @bigNewItemUID bigint =0;
		declare @bigOldEquipCharacterUID bigint = 0;
		declare @tblLastUpdateQueryStr table (Seq int identity(1,1), QueryStr nvarchar(max));
		
		while @intItemMaxSeq >= 1
		begin

			select @bigOldItemUID = ItemUID, @bigOldEquipCharacterUID = EquipCharacterUID from #ItemListTmp where Seq = @intItemMaxSeq;
			set @bigNewItemUID = next value for [dbo].[sqInventoryUID]

			if @isInfo = 1
			begin					   	 		
				print N'--###########################################################################'
				print N'-- ���� ������ UID : ' + cast(@bigOldItemUID as nvarchar(56))
				print N'-- �ű� ������ UID : ' + cast(@bigNewItemUID as nvarchar(56))
				print N'--###########################################################################'		
			end

			
			/* ------------------------------------------------------------------
			���� ���̺��� ���� �ʾ� ���� ó�� 
			Inventory,InventoryStat,CharacterEquipPreset
			EquipGemSocket =  ����ϴ��� üũ �ʿ�
			------------------------------------------------------------------ */	
			set @SearchCondition = 'ItemUID = ''' + cast(@bigOldItemUID as nvarchar(56)) + ''' and [AccountUID] = ''' + cast(@bigSrcAccountUID as nvarchar(56)) + ''''
			set @ReplaceValue2  = '''' + convert(nvarchar(26), @bigNewItemUID) + '''';
		
			set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert
						@ObjectName= @nvcTableName
					,	@SearchCondition= @SearchCondition
					,	@ReplaceColumn1  = ''AccountUID''
					,	@ReplaceValue1 = @ReplaceValue1	
					,	@ReplaceColumn2 = ''ItemUID''
					,	@ReplaceValue2 = @ReplaceValue2
					,	@PrintGeneratedCode = @PrintGeneratedCode
					,	@IsExecute =@IsExecute
					,	@IsLinedServer =@IsLinedServer
					,	@ExecuteDatabase = @varTargetDatabase'
					
					set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
											, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
					exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
											@nvcTableName = 'Inventory',
											@SearchCondition = @SearchCondition,
											@ReplaceValue1 = @ReplaceValue1,
											@ReplaceValue2 = @ReplaceValue2,
											@ReplaceValue3 = @ReplaceValue3,
											@PrintGeneratedCode = @PrintGeneratedCode,
											@IsExecute = @IsExecute,
											@IsLinedServer = @IsLinedServer,
											@varTargetDatabase = @varTargetDatabase;  ;
		
		
		
			set @SearchCondition = 'ItemUID = ''' + cast(@bigOldItemUID as nvarchar(56)) + ''''
			set @nvcQueryStr = 'exec '+ iif(@varLinkedServer is null, '', '['+ @varLinkedServer + '].') + '['+ @varRemoteDatabase + ']..sp_GenerateInsert
					@ObjectName= @nvcTableName
				,	@SearchCondition= @SearchCondition
				,	@ReplaceColumn1  = ''AccountUID''
				,	@ReplaceValue1 = @ReplaceValue1	
				,	@ReplaceColumn2 = ''ItemUID''
				,	@ReplaceValue2 = @ReplaceValue2
				,	@PrintGeneratedCode = @PrintGeneratedCode
				,	@IsExecute =@IsExecute
				,	@IsLinedServer =@IsLinedServer
				,	@ExecuteDatabase = @varTargetDatabase'
				
				set @nvcParmDefinition = N'@nvcTableName nvarchar(64), @SearchCondition nvarchar(1024), @ReplaceValue1 nvarchar(261), @ReplaceValue2 nvarchar(261)
										, @ReplaceValue3 nvarchar(261), @PrintGeneratedCode bit, @IsExecute bit, @IsLinedServer bit, @varTargetDatabase varchar(64)';
				/*
				exec sp_executesql @nvcQueryStr, @nvcParmDefinition, 
										@nvcTableName = 'InventoryStat',
										@SearchCondition = @SearchCondition,
										@ReplaceValue1 = @ReplaceValue1,
										@ReplaceValue2 = @ReplaceValue2,
										@ReplaceValue3 = @ReplaceValue3,
										@PrintGeneratedCode = @PrintGeneratedCode,
										@IsExecute = @IsExecute,
										@IsLinedServer = @IsLinedServer,
										@varTargetDatabase = @varTargetDatabase;  
				*/
			
			if @bigOldEquipCharacterUID > 0
			begin
				insert into @tblLastUpdateQueryStr(QueryStr)
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_1 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_1  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_2 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_2  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_3 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_3  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_4 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_4  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_5 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_5  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_6 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_6  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_7 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_7  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_8 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_8  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_9 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_9  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_10 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_10 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_11 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_11 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_12 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_12 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_13 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_13 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_14 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_14 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_15 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_15 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_16 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_16 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_17 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_17 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_18 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_18 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_19 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_19 = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				select 'update ['+ @varTargetDatabase +'].dbo.CharacterEquipPreset set ItemUID_20 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_20 = ' + cast(@bigOldItemUID as varchar(max)) + ';'
				
				--insert into @tblLastUpdateQueryStr(QueryStr)
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_1 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_1  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_2 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_2  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_3 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_3  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_4 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_4  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_5 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_5  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_6 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_6  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_7 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_7  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_8 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_8  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_9 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID_9  = ' + cast(@bigOldItemUID as varchar(max)) + ';' union all 
				--select 'update ['+ @varTargetDatabase +'].dbo.CharacterDefensePreset set ItemUID_10 = ' + cast(@bigNewItemUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and ItemUID_10 = ' + cast(@bigOldItemUID as varchar(max)) + ';'
			

				--select @bigNewCharacterUID = NewCharacterUID from #CharacterListTmp where CharacterUID = @bigOldEquipCharacterUID;			
				--insert into @tblLastUpdateQueryStr(QueryStr)
				--select 'update ['+ @varTargetDatabase +'].dbo.Inventory set ______EC_UID = ' + cast(@bigNewCharacterUID as varchar(max)) + ' where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ' and  ItemUID  = ' + cast(@bigNewItemUID as varchar(max)) + ';'				
			end			
--			select @bigOldEquipCharacterUID, @intItemMaxSeq;

			set @bigOldEquipCharacterUID = 0;						
			set @intItemMaxSeq -= 1;
		end

		--ģ�� ���� �ʱ�ȭ
		insert into @tblLastUpdateQueryStr(QueryStr)
		select 'update ['+ @varTargetDatabase +'].[dbo].[Account] set FriendCount= 0, RequestFriendCount = 0 where AccountUID = ' + cast( @bigNewAccountUID as varchar(max)) + ';'				

				
		if @isInfo = 1
		begin
			print N'--###########################################################################'
			print N'-- CharacterEquipPreset ó��'
			print N'--###########################################################################'
		end
		--print '/*'
		declare @intLastSeq int = (select max(seq) from @tblLastUpdateQueryStr)
		while @intLastSeq >= 1
		begin
				
			select @nvcQueryStr = QueryStr from @tblLastUpdateQueryStr where Seq = @intLastSeq;
			
			if @IsExecute = 1
				begin
					exec ('USE ['+ @varTargetDatabase + ']; ' + @nvcQueryStr)
				end
			else
				begin
					print @nvcQueryStr;
				end
			
			set @intLastSeq -= 1;
		end
		--print '*/'

		set @intCopyCount = @intCopyCount -1;
		print '-------------------------------------------------------------------'
		print '---' + cast(@intCopyCount as varchar(24))
		print '---' + CONVERT(CHAR(23), getdate(), 21)
		print '-------------------------------------------------------------------'
--end
	
	

print N'/*'
print N'linked server�� �����ϼ���~'
print N'exec master.dbo.sp_dropserver @server=N''192.168.100.130,1433'', @droplogins=''droplogins'''
print N'*/'

