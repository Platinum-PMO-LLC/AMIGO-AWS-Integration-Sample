public class SObjectFieldExporter {
    
    public static void exportAllSObjectsWithFieldsToCSV() {
        // Get all sObjects in the org
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<String> sObjectNames = new List<String>(globalDescribe.keySet());
        sObjectNames.sort();
        
        // Create CSV header
        String csvContent = 'Custom Object API Name,Object Label,Custom Field API Names\n';
        
        // Process each sObject
        for(String sObjectName : sObjectNames) {
            Schema.SObjectType sObjectType = globalDescribe.get(sObjectName);
            Schema.DescribeSObjectResult sObjectDescribe = sObjectType.getDescribe();
            
            // Skip if not a custom object or not queryable
            if(!sObjectDescribe.isCustom() || !sObjectDescribe.isQueryable()) {
                continue;
            }
            
            // Get all fields for the sObject
            Map<String, Schema.SObjectField> fieldMap = sObjectDescribe.fields.getMap();
            List<String> customFieldApiNames = new List<String>();
            
            // Collect only custom fields
            for(String fieldName : fieldMap.keySet()) {
                Schema.SObjectField field = fieldMap.get(fieldName);
                if(field.getDescribe().isCustom()) {
                    customFieldApiNames.add(fieldName);
                }
            }
            customFieldApiNames.sort();
            
            // Only add to CSV if the object has custom fields
            if(!customFieldApiNames.isEmpty()) {
                csvContent += '"' + sObjectName + '","' + sObjectDescribe.getLabel() + '","' + 
                              String.join(customFieldApiNames, ',') + '"\n';
            }
        }
        
        // Create a ContentVersion record to store the CSV
        ContentVersion csvFile = new ContentVersion();
        csvFile.Title = 'Custom_Objects_Fields_Export_' + Datetime.now().format('yyyy-MM-dd_HH-mm-ss') + '.csv';
        csvFile.PathOnClient = csvFile.Title;
        csvFile.VersionData = Blob.valueOf(csvContent);
        insert csvFile;
        
        // Get the ContentDocumentId
        csvFile = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :csvFile.Id LIMIT 1];
        
        // Generate download URL
        String orgDomainUrl = System.Url.getOrgDomainUrl().toExternalForm();
        String downloadUrl = orgDomainUrl + '/sfc/servlet.shepherd/document/download/' + csvFile.ContentDocumentId;
        
        System.debug('CSV file created with ContentDocumentId: ' + csvFile.ContentDocumentId);
        System.debug('Download URL: ' + downloadUrl);
    }
}