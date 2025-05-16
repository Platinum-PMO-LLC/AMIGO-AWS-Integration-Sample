public with sharing class RecordContextController {
    /**
     * Get comprehensive record data including related records
     * @param recordId The ID of the record to retrieve
     * @return Map containing record data and related records
     */
    @AuraEnabled
    public static Map<String, Object> getRecordContext(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required');
        }
        
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Get the object type from the record ID
            String objectApiName = getObjectApiName(recordId);
            result.put('objectApiName', objectApiName);
            
            // Get the record fields dynamically
            Map<String, Object> recordFields = getRecordFields(recordId, objectApiName);
            result.put('record', recordFields);
            
            // Get related records
            Map<String, Object> relatedRecords = getRelatedRecords(recordId, objectApiName);
            result.put('relatedRecords', relatedRecords);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving record context: ' + e.getMessage());
        }
    }
    
    /**
     * Process the user prompt with record context
     * @param recordId The ID of the record
     * @param prompt The user's prompt text
     * @return Processed response
     */
    @AuraEnabled
    public static String processPrompt(String recordId, String prompt) {
        if (String.isBlank(recordId) || String.isBlank(prompt)) {
            throw new AuraHandledException('Record ID and prompt are required');
        }
        
        try {
            // Get record context
            Map<String, Object> recordContext = getRecordContext(recordId);
            
            // Here you would typically call an external API or service with the prompt and context
            // For demo purposes, we'll return a simulated response
            String response = generateSimulatedResponse(prompt, recordContext);
            
            return response;
        } catch (Exception e) {
            throw new AuraHandledException('Error processing prompt: ' + e.getMessage());
        }
    }
    
    /**
     * Get the API name of the object based on record ID
     */
    private static String getObjectApiName(String recordId) {
        if (String.isBlank(recordId)) return null;
        
        // Get the object type from the record ID prefix
        String keyPrefix = recordId.substring(0, 3);
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        for (Schema.SObjectType sObjectType : globalDescribe.values()) {
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            if (describeResult.getKeyPrefix() == keyPrefix) {
                return describeResult.getName();
            }
        }
        
        return null;
    }
    
    /**
     * Get record fields dynamically
     */
    private static Map<String, Object> getRecordFields(String recordId, String objectApiName) {
        if (String.isBlank(recordId) || String.isBlank(objectApiName)) return new Map<String, Object>();
        
        // Get object fields
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());
        
        // Build dynamic SOQL
        String soqlQuery = 'SELECT ' + String.join(fieldNames, ',') + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        
        // Execute query
        SObject record;
        try {
            record = Database.query(soqlQuery);
        } catch (Exception e) {
            // If the dynamic query fails (possibly due to field level security or too many fields),
            // fall back to a simplified query with common fields
            soqlQuery = 'SELECT Id, Name FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
            record = Database.query(soqlQuery);
        }
        
        // Convert to map
        Map<String, Object> recordMap = new Map<String, Object>();
        for (String field : record.getPopulatedFieldsAsMap().keySet()) {
            recordMap.put(field, record.get(field));
        }
        
        return recordMap;
    }
    
    /**
     * Get related records
     */
    private static Map<String, Object> getRelatedRecords(String recordId, String objectApiName) {
        if (String.isBlank(recordId) || String.isBlank(objectApiName)) return new Map<String, Object>();
        
        Map<String, Object> relatedRecordsMap = new Map<String, Object>();
        
        // Get object schema
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        
        // Get child relationships
        List<Schema.ChildRelationship> childRelationships = objectDescribe.getChildRelationships();
        
        // Limit to a reasonable number to avoid hitting governor limits
        Integer relationshipLimit = 5;
        Integer currentCount = 0;
        
        for (Schema.ChildRelationship relationship : childRelationships) {
            if (currentCount >= relationshipLimit) break;
            
            Schema.DescribeSObjectResult childObjectDescribe = relationship.getChildSObject().getDescribe();
            
            // Skip certain system objects
            if (childObjectDescribe.getName().startsWith('History') || 
                childObjectDescribe.getName().startsWith('Share') ||
                !childObjectDescribe.isAccessible()) {
                continue;
            }
            
            // Get related records
            String relatedListName = childObjectDescribe.getName();
            String relationshipField = relationship.getField().getDescribe().getName();
            
            try {
                // Build dynamic SOQL for child records
                String childSoql = 'SELECT Id, Name FROM ' + relatedListName + 
                                  ' WHERE ' + relationshipField + ' = :recordId LIMIT 100';
                
                List<SObject> relatedRecords = Database.query(childSoql);
                
                if (!relatedRecords.isEmpty()) {
                    List<Map<String, Object>> recordsList = new List<Map<String, Object>>();
                    
                    for (SObject relatedRecord : relatedRecords) {
                        Map<String, Object> recordMap = new Map<String, Object>();
                        for (String field : relatedRecord.getPopulatedFieldsAsMap().keySet()) {
                            recordMap.put(field, relatedRecord.get(field));
                        }
                        recordsList.add(recordMap);
                    }
                    
                    relatedRecordsMap.put(relatedListName, recordsList);
                    currentCount++;
                }
            } catch (Exception e) {
                // Skip this relationship if there's an error
                System.debug('Error querying related records for ' + relatedListName + ': ' + e.getMessage());
            }
        }
        
        return relatedRecordsMap;
    }
    
    /**
     * Generate a simulated response for demo purposes
     * In a real implementation, this would call an external API
     */
    private static String generateSimulatedResponse(String prompt, Map<String, Object> recordContext) {
        String objectApiName = (String)recordContext.get('objectApiName');
        Map<String, Object> record = (Map<String, Object>)recordContext.get('record');
        Map<String, Object> relatedRecords = (Map<String, Object>)recordContext.get('relatedRecords');
        
        // Build a response that shows we're using the context
        String response = '<h2>Response to your prompt:</h2>';
        response += '<p><strong>Your prompt:</strong> ' + prompt + '</p>';
        response += '<p><strong>Object Type:</strong> ' + objectApiName + '</p>';
        
        if (record.containsKey('Name')) {
            response += '<p><strong>Record Name:</strong> ' + record.get('Name') + '</p>';
        }
        
        // Add some information about related records
        response += '<h3>Related Records Summary:</h3><ul>';
        for (String relatedObject : relatedRecords.keySet()) {
            List<Map<String, Object>> records = (List<Map<String, Object>>)relatedRecords.get(relatedObject);
            response += '<li>' + relatedObject + ': ' + records.size() + ' records</li>';
        }
        response += '</ul>';
        
        // Add a simulated analysis
        response += '<h3>Analysis:</h3>';
        response += '<p>Based on the context of this ' + objectApiName + ' record and your prompt, ';
        response += 'here is a simulated response that demonstrates how the component would work with ';
        response += 'an actual integration to an AI service or other external API.</p>';
        
        return response;
    }
}