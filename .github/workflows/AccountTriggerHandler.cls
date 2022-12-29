/*
 * Copyright (c) 2020 Salesforce, Inc. All rights reserved.
 */
public without sharing class AccountTriggerHandler{

	/**
	 * @description This method is used to determine account's with updates to it's recordtype.
	 * @author A. Recio
	 * @date 03.DEC.2012
	 * @param accListNew List of Trigger.new accounts
	 * @param accMapOld Map of Trigger.old accounts
	 * @return void
	*/
	public class CustomException extends Exception {}

	public static void normalizeCompanyName(Account[] newValues, Account[] oldValues) {
		for (Account account: newValues) {
			account.Name_Normalized__c = normalizeCompanyName(account.Name);
		}
	}

	@testVisible
	private static String normalizeCompanyName(String companyName) {
		String name = companyName
			.toLowerCase()
			.stripHtmlTags()
			.replaceAll('[,+]', ' ')
			.replaceAll('([^ .]+)\\.(?:com|co\\.uk|co\\.in|co|in|net|org) ?', '$1')
			.replaceAll('&? ?\\b(?:ag|inc|llp|ltda|ltd|corp|co|kg|llc|l\\.l\\.c|gmbh|pty|pvt|s\\.a|s\\.a|spa|s\\.p\\.a|srl|s\\.r\\.l)\\b\\.?', ' ')
			.normalizeSpace();

		return name;
	}

	public static List<Account> HasTypeUpdates(List<Account> accListNew,Map<Id,Account>accMapOld,Boolean fromBeforeUpdate){
		// Variable Declaration
		List<Account>accWithUpdateList = new List<Account>();
		Account oldAccVar = new Account();
		Boolean hasRecTypeUpdate;
		Boolean hasTypeUpdate;

		// Setup Master Accounts
		Map<String,Master_User__c> masterUserMap = Master_User__c.getAll();
		Master_User__c usrVarCustomer = masterUserMap.get('Customer Owner');
		Master_User__c usrVarPartner = masterUserMap.get('Partner Owner');
		Master_User__c usrVarEmployee = masterUserMap.get('Employee Owner');

		// Get Support Contractor recordtype of sobjectType Account
		Map<String, Schema.RecordTypeInfo> accRecTypesByName = Account.SObjectType.getDescribe().getRecordTypeInfosByName();
		Map<ID, Schema.RecordTypeInfo> accRecTypesById = Account.SObjectType.getDescribe().getRecordTypeInfosByID();

		// Loop within new accounts
		for(Account accVar:accListNew){
			hasRecTypeUpdate = false;
			hasTypeUpdate = false;
			// Get old Account Record
			oldAccVar = accMapOld.get(accVar.Id);

			// Check if account is support contractor
			if(oldAccVar.type == 'Partner' && oldAccVar.RecordTypeId == accRecTypesByName.get('Support Contractor').getRecordTypeId())
			{
				if(fromBeforeUpdate){
					accVar.Type = oldAccVar.type;
					accVar.RecordTypeId = accRecTypesByName.get('Support Contractor').getRecordTypeId();
				}// End If
			}else{
				// Determine if recordtype is updated
				if(oldAccVar.RecordTypeId != accVar.RecordtypeId ){
					hasRectypeUpdate = true;
				}// End If

				// Determine if type is updated
				if(oldAccVar.Type != accVar.Type){
					hasTypeUpdate = true;
				}// End If

				// sync type with recordtype
				if(hasRectypeUpdate == true && hastypeUpdate == false){
					if(accRecTypesById.get(accVar.recordTypeId).getName()!='Support Contractor'){
						accVar.Type = accRecTypesById.get(accVar.recordTypeId).getName();
					}// End If
				}// End If

				// sync recordtype with type
				if(hastypeUpdate == true && hasRectypeUpdate == false){
					accVar.RecordTypeId = accRecTypesByName.get(accVar.Type).getRecordTypeId();
				}// End If

				// throw exception if both field have updates and the value is not sync
				if(hastypeUpdate == true && hasRectypeUpdate == true){
					if(accRecTypesById.get(accVar.recordTypeId).getName() != accVar.Type){
						throw new CustomException('The Type and Record Type change on Account do not match.');
					}// End If
				}// End If

				if(hasRectypeUpdate == true || hastypeUpdate == true){
					// Contact Sync
					if(fromBeforeUpdate){
						if(accVar.Type == 'Customer'){
								accVar.OwnerId = usrVarCustomer.RecordId__c;
						}else if(accVar.Type == 'Employee'){
								accVar.OwnerId = usrVarEmployee.RecordId__c;
						}else if(accVar.Type == 'Partner'){
								accVar.OwnerId = usrVarPartner.RecordId__c;
						}// End Else
					}// End If
					accWithUpdateList.add(accVar);
				}// End If
			}// End Else
		}// End for

		return accWithUpdateList;
	}// End HasFieldUpdates Method

	/**
	 * @description This method is used to update child contacts of accounts with update to type or recordtype
	 * @author A. Recio
	 * @date 03.DEC.2012
	 * @param accWithUpdateList List of Account with updates to type/recordtype
	 * @return void
	*/
	public static void UpdateChildContacts(List<Account> accWithUpdateList){
		// Variable Declaration
		Set<Id>accId = new Set<Id>();
		List<Test_Taker__c>conList = new List<Test_Taker__c>();
		List<Test_Taker__c>conListUpdate = new List<Test_Taker__c>();
		Map<Id, Account> accWithUpdateMap = new Map<Id, Account>();
		String typeStr;

		// Setup Master Accounts
		Map<String,Master_User__c> masterUserMap = Master_User__c.getAll();
		Master_User__c usrVarCustomer = masterUserMap.get('Customer Owner');
		Master_User__c usrVarPartner = masterUserMap.get('Partner Owner');
		Master_User__c usrVarEmployee = masterUserMap.get('Employee Owner');

		// Get Support Contractor recordtype of sobjectType Contact
		Map<String, Schema.RecordTypeInfo> conRecTypesByName = Test_Taker__c.SObjectType.getDescribe().getRecordTypeInfosByName();
		String conSuppConRecTypeId = conRecTypesByName.get('Support Contractor').getRecordTypeId();

		// Get Support Contractor recordtype of sobjectType Account
		Map<String, Schema.RecordTypeInfo> accRecTypesByName = Account.SObjectType.getDescribe().getRecordTypeInfosByName();
		String accSuppConRecTypeId = accRecTypesByName.get('Support Contractor').getRecordTypeId();

		// Wrapper class variables
		TestTakers.SupportContractorWrapper suppWrapperVar = new TestTakers.SupportContractorWrapper();
		list<Account>knownContractorList = [Select RecordTypeId,Contractor_Name__c, BillingCountry, Contractor_Location_Cities__c from Account where type = 'Partner' and RecordTypeId = :accSuppConRecTypeId];

		// Create account set and map
		for(Account accVar:accWithUpdateList){
			accId.add(accVar.Id);
			accWithUpdateMap.put(accVar.Id, accVar);
		}// End For

		conList = [Select Id, Account__c, Type__c, RecordTypeId, OwnerId, Test_Provider_User_Company_Name__c,Mailing_City__c,Mailing_Country__c from Test_Taker__c where Account__c In :accId];
		for(Test_Taker__c conVar:conList){
			Boolean conVarChanged = false;
			typeStr = accWithUpdateMap.get(conVar.Account__c).Type;
			if(conVar.Type__c != typeStr){
				conVar.Type__c = typeStr;
				conVar.RecordTypeId = conRecTypesByName.get(typeStr).getRecordTypeId();
				conVarChanged = true;
			}
			if(typeStr == 'Customer' && conVar.OwnerId != usrVarCustomer.RecordId__c){
				conVar.OwnerId = usrVarCustomer.RecordId__c;
				conVarChanged = true;
			}else if(typeStr == 'Employee' && conVar.OwnerId != usrVarEmployee.RecordId__c){
				conVar.OwnerId = usrVarEmployee.RecordId__c;
				conVarChanged = true;
			}else if(typeStr == 'Partner' && conVar.OwnerId != usrVarPartner.RecordId__c){
				conVar.OwnerId = usrVarPartner.RecordId__c;
				// Contractor Parsing Logic
				for(Account supportVar:knownContractorList){
					suppWrapperVar.oAcc = supportVar;
					suppWrapperVar.oCon = conVar;
					suppWrapperVar.accSuppConRecTypeId = accSuppConRecTypeId;
					suppWrapperVar.conRecType = conSuppConRecTypeId;
					suppWrapperVar.conPartneOwnerId = usrVarPartner.RecordId__c;
					if(TestTakers.parseSupportContractor(suppWrapperVar)){
						conVar.RecordTypeId = conSuppConRecTypeId;
						break;
					}// End If
				}// End For
				conVarChanged = true;
			}// End Else
			if(conVarChanged){
				conListUpdate.add(conVar);
			}
		}// End For
		if(conListUpdate.size() > 0){
			update conListUpdate;
		}
	}// End UpdateChildContacts

	public static void assignRoleToAccountOwners(List<Account> accts) {
		// in the case of future/ batch context not processing our check
		if(System.isFuture() || System.isBatch()) {
			return;
		}
		
		Set<Id> accIds = new Set<Id>();
		for(Account acct : accts) {
			accIds.add(acct.Id);
		}
		assignRoleToAccountOwners(JSON.serialize(accIds));
	}

	@future
	public static void assignRoleToAccountOwners(String accIdSetJSON) {
		Set<Id> accIds = (Set<Id>)JSON.deserialize(accIdSetJSON, Set<Id>.class);
		List<Account> accts = [SELECT Id, Name, Owner.Id, Owner.UserRole.Id FROM Account WHERE ID IN :accIds];
		Id automatedProcessUserId = [SELECT Id FROM User WHERE Name = 'Automated Process'].Id;
		Set<Id> withoutRoleOwnerIds = new Set<Id>();
		for(Account acct: accts){
			if(acct.Owner.UserRoleId == null && acct.OwnerId != automatedProcessUserId) {
				withoutRoleOwnerIds.add(acct.OwnerId);
			}
		}

		if(withoutRoleOwnerIds.size() > 0) {
			List<UserRole> userRoles = [SELECT Id, Name FROM UserRole WHERE Name = 'Experience Cloud Account Owner' LIMIT 1];
			if(!userRoles.isEmpty()) {
				List<User> withoutRoleUsers = [SELECT Id, UserRoleId, Name FROM User WHERE ID IN :withoutRoleOwnerIds];
				for (User usr : withoutRoleUsers) {
					usr.UserRoleId = userRoles[0].Id;
				}
				update withoutRoleUsers;
			}
		}
	}

	public static void afterInsert(List<Account> accounts) {
		maintainPartnerEnable(accounts, new Map<Id, Account>(), true);
	}

	public static void afterUpdate(List<Account> accounts, Map<Id,Account> oldMap ) {
		maintainPartnerEnable(accounts, oldMap, false);
	}

	static void maintainPartnerEnable(List<Account> accounts, Map<Id,Account> oldMap, Boolean isInsert) {
		// in the case of future/ batch context not processing our check
		if(System.isFuture() || System.isBatch()){
			return;
		}
		// getting Id of Accout's Community Group record Type
		Id accRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Community Group').getRecordTypeId();
		Set<Id> accIds = new Set<Id>();
		for(Account acc: accounts){
			if(acc.RecordTypeId == accRecTypeId
			   && acc.IsPartner == false) {
				accIds.add(acc.Id);
			}
		}
		// not calling from future context
		if(!accIds.isEmpty()){
			makePartnerEnable(JSON.serialize(accIds));
		}
	}

	@future
	static void makePartnerEnable(String accIdSetJSON) {
		Id accRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Community Group').getRecordTypeId();

		Set<Id> accIds = (Set<Id>)JSON.deserialize(accIdSetJSON, Set<Id>.class);
		List<Account> accounts = [SELECT Id FROM Account WHERE RecordTypeId=:accRecTypeId AND Id in :accIds
								  AND IsPartner = FALSE];

		for(Account acc: accounts){
			acc.IsPartner = true;
		}
		update accounts;
	}
}