public with sharing class RecordContextController {
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
            
            // Get related records using our improved method
            Map<String, Object> relatedRecords = getRelatedRecords(recordId, objectApiName);
            result.put('relatedRecords', relatedRecords);
            
            // Add a summary for debugging
            Integer relatedObjectCount = relatedRecords.size();
            List<String> relatedObjectNames = new List<String>(relatedRecords.keySet());
            System.debug(JSON.serializePretty(result));
            
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in getRecordContext: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving record context: ' + e.getMessage());
        }
    }
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

            System.debug('Simulated response: ' + JSON.serializePretty(response));
            
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
    public static Map<String, Object> getRelatedRecords(String recordId, String objectApiName) {
        if (String.isBlank(recordId) || String.isBlank(objectApiName)) return new Map<String, Object>();
        
        Map<String, Object> relatedRecordsMap = new Map<String, Object>();
        
        // Get object schema
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        
        // Get child relationships
        List<Schema.ChildRelationship> childRelationships = objectDescribe.getChildRelationships();
        
        // Limit to a reasonable number to avoid hitting governor limits
        Integer relationshipLimit = 5;
        Integer currentCount = 0;
        
        // Maintain a set of known problematic objects or relationship fields
        Set<String> nonQueryableObjects = new Set<String>{
            'OutgoingEmail', 'EmailMessage', 'ContentDocumentLink'
        };
        
        Set<String> nonFilterableFields = new Set<String>{
            'RelatedToId', 'LinkedEntityId'
        };
        
        for (Schema.ChildRelationship relationship : childRelationships) {
            if (currentCount >= relationshipLimit) break;
            
            Schema.DescribeSObjectResult childObjectDescribe = relationship.getChildSObject().getDescribe();
            String childObjectName = childObjectDescribe.getName();
            String relationshipField = relationship.getField().getDescribe().getName();
            
            // Skip certain system objects and objects that don't support queries
            if (childObjectName.endsWith('ChangeEvent') || 
                childObjectName.startsWith('History') || 
                childObjectName.startsWith('Share') ||
                !childObjectDescribe.isAccessible() ||
                !childObjectDescribe.isQueryable() ||
                nonQueryableObjects.contains(childObjectName) ||
                nonFilterableFields.contains(relationshipField)) {
                
                // System.debug('Skipping relationship ' + childObjectName + '.' + relationshipField + 
                            //  ' - Object may not support querying or field may not be filterable');
                continue;
            }
            
            // Get related records
            String relatedListName = childObjectName;
            
            try {
                // Get the field map for this object
                Map<String, Schema.SObjectField> fieldMap = childObjectDescribe.fields.getMap();
                
                // Check if the relationship field is filterable
                if (!fieldMap.get(relationshipField).getDescribe().isFilterable()) {
                    System.debug('Skipping relationship ' + childObjectName + '.' + relationshipField + 
                                ' - Field is not filterable');
                    continue;
                }
                
                // Determine which fields to query
                List<String> fieldsToQuery = new List<String>{'Id'};
                
                // Check if Name field exists and add it if it does
                if (fieldMap.containsKey('Name')) {
                    fieldsToQuery.add('Name');
                } else {
                    // Look for alternative display fields
                    for (String potentialField : new List<String>{
                        'Subject', 'Title', 'CaseNumber', 'OrderNumber', 'TaskSubject',
                        'Description', 'LineItemNumber', 'ApprovalName'
                    }) {
                        if (fieldMap.containsKey(potentialField)) {
                            fieldsToQuery.add(potentialField);
                            break;
                        }
                    }
                }
                
                // Build dynamic SOQL for child records
                String childSoql = 'SELECT ' + String.join(fieldsToQuery, ',') + 
                                ' FROM ' + relatedListName + 
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
                    System.debug('Successfully queried ' + relatedRecords.size() + ' ' + relatedListName + ' records');
                }
            } catch (Exception e) {
                // Skip this relationship if there's an error, but log it for debugging
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