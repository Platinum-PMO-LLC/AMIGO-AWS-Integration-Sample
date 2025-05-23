public with sharing class RecordContextController {

    @AuraEnabled
    public static Map<String, Object> getRecordContext(String recordId, String prompt) { // Added prompt here
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required');
        }
        
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            String objectApiName = getObjectApiName(recordId);
            System.debug('Object API Name: ' + objectApiName);
            result.put('objectApiName', objectApiName);

            Map<String, Object> recordFields = getRecordFields(recordId, objectApiName);
            result.put('record', recordFields);

            // Extract desired related objects from prompt
            Set<String> desiredRelatedObjects = extractDesiredObjectsFromPrompt(prompt, objectApiName);
            System.debug('Desired related objects from prompt: ' + JSON.serialize(desiredRelatedObjects));

            Map<String, Object> relatedRecords = getRelatedRecords(recordId, objectApiName, desiredRelatedObjects);
            result.put('relatedRecords', relatedRecords);

            // These debug lines will now reflect the filtered related records
            Integer relatedObjectCount = relatedRecords.size();
            List<String> relatedObjectNames = new List<String>(relatedRecords.keySet());
            System.debug('Actual related objects fetched: ' + relatedObjectCount + ' - ' + JSON.serialize(relatedObjectNames));
            System.debug('Final record context: ' + JSON.serializePretty(result));
            
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
            // Get record context, now filtered by prompt
            Map<String, Object> recordContext = getRecordContext(recordId, prompt);
            
            String response = getResponseBody(prompt, recordContext);

            System.debug('Simulated response: ' + JSON.serializePretty(response));
            
            return response;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in processPrompt: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Error processing prompt: ' + e.getMessage());
        }
    }
    
    /**
     * Extracts potential SObject API names from a user prompt.
     * Enhanced to handle namespaced objects, plurals, and labels.
     */
    private static Set<String> extractDesiredObjectsFromPrompt(String prompt, String parentObjectApiName) {
        Set<String> desiredObjects = new Set<String>();
        if (String.isBlank(prompt) || String.isBlank(parentObjectApiName)) {
            System.debug('Prompt or parentObjectApiName is blank. No related objects will be extracted for filtering.');
            return desiredObjects;
        }

        System.debug('Attempting to extract desired objects from prompt: "' + prompt + '" for parent: ' + parentObjectApiName);

        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectApiName);
        if (parentType == null) {
            System.debug('Invalid parentObjectApiName in extractDesiredObjectsFromPrompt: ' + parentObjectApiName);
            return desiredObjects;
        }
        Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
        List<Schema.ChildRelationship> childRelationships = parentDescribe.getChildRelationships();
        String promptLowerCase = prompt.toLowerCase();

        for (Schema.ChildRelationship cr : childRelationships) {
            Schema.DescribeSObjectResult childObjectDescribe = cr.getChildSObject().getDescribe();
            String childApiName = childObjectDescribe.getName();
            String childLabel = childObjectDescribe.getLabel();
            String childLabelPlural = childObjectDescribe.getLabelPlural();
            
            System.debug('Checking object: ' + childApiName + ' (Label: ' + childLabel + ', Label Plural: ' + childLabelPlural + ')');
            
            Boolean found = false;

            // 1. Try exact API name match
            if (promptLowerCase.contains(childApiName.toLowerCase())) {
                desiredObjects.add(childApiName);
                System.debug('Prompt extraction: Found by exact API name: ' + childApiName);
                found = true;
            }
            
            // 2. Try object label matches (singular and plural)
            if (!found && String.isNotBlank(childLabel)) {
                String labelRegex = '\\b' + Pattern.quote(childLabel.toLowerCase()) + '\\b';
                System.Pattern labelPattern = System.Pattern.compile(labelRegex);
                System.Matcher labelMatcher = labelPattern.matcher(promptLowerCase);
                if (labelMatcher.find()) {
                    desiredObjects.add(childApiName);
                    System.debug('Prompt extraction: Found by label: ' + childLabel + ' (maps to ' + childApiName + ')');
                    found = true;
                }
            }
            
            if (!found && String.isNotBlank(childLabelPlural)) {
                String labelPluralRegex = '\\b' + Pattern.quote(childLabelPlural.toLowerCase()) + '\\b';
                System.Pattern labelPluralPattern = System.Pattern.compile(labelPluralRegex);
                System.Matcher labelPluralMatcher = labelPluralPattern.matcher(promptLowerCase);
                if (labelPluralMatcher.find()) {
                    desiredObjects.add(childApiName);
                    System.debug('Prompt extraction: Found by plural label: ' + childLabelPlural + ' (maps to ' + childApiName + ')');
                    found = true;
                }
            }

            // 3. Try namespaced object name extraction (for custom objects)
            if (!found && childApiName.contains('__c')) {
                // Extract the base name from namespaced custom object
                // Format: Namespace__ObjectName__c or ObjectName__c
                String baseName = childApiName;
                if (baseName.endsWith('__c')) {
                    baseName = baseName.substring(0, baseName.length() - 3); // Remove __c
                }
                if (baseName.contains('__')) {
                    // Has namespace, get the part after the last __
                    Integer lastIndex = baseName.lastIndexOf('__');
                    baseName = baseName.substring(lastIndex + 2);
                }
                
                // Try matching the base name (singular and with 's' for plural)
                String baseNameRegex = '\\b' + Pattern.quote(baseName.toLowerCase()) + 's?\\b';
                System.Pattern baseNamePattern = System.Pattern.compile(baseNameRegex);
                System.Matcher baseNameMatcher = baseNamePattern.matcher(promptLowerCase);
                if (baseNameMatcher.find()) {
                    desiredObjects.add(childApiName);
                    System.debug('Prompt extraction: Found by base name: ' + baseName + ' (maps to ' + childApiName + ')');
                    found = true;
                }
            }

            // 4. Try relationship name matching
            if (!found) {
                String relationshipName = cr.getRelationshipName();
                if (String.isNotBlank(relationshipName)) {
                    String relationshipNameRegex = '\\b' + Pattern.quote(relationshipName.toLowerCase()) + '\\b';
                    System.Pattern relationshipNamePattern = System.Pattern.compile(relationshipNameRegex);
                    System.Matcher relationshipNameMatcher = relationshipNamePattern.matcher(promptLowerCase);

                    if (relationshipNameMatcher.find()) {
                        desiredObjects.add(childApiName);
                        System.debug('Prompt extraction: Found by relationship name: ' + relationshipName + ' (maps to ' + childApiName + ')');
                    }
                }
            }
        }
        System.debug('Prompt extraction: Final desired objects: ' + JSON.serialize(desiredObjects));
        return desiredObjects;
    }

    public static String getObjectApiName (Id recordId) {
        return recordId.getSobjectType().getDescribe().getName();
    }
    
    private static Map<String, Object> getRecordFields(String recordId, String objectApiName) {
        if (String.isBlank(recordId) || String.isBlank(objectApiName)) return new Map<String, Object>();
        
        Map<String, Schema.SObjectField> sObjectFieldMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>();
        
        for(String fieldKey : sObjectFieldMap.keySet()){
            Schema.DescribeFieldResult fieldDescribe = sObjectFieldMap.get(fieldKey).getDescribe();
            // Corrected condition: removed non-existent isCompound() and rely on SoapType checks
            if(fieldDescribe.isAccessible() && 
               fieldDescribe.getSoapType() != Schema.SoapType.ADDRESS && // Explicitly skip Address compound
               fieldDescribe.getSoapType() != Schema.SoapType.LOCATION  // Explicitly skip Location compound
              ) {
                 // Additional check for specific problematic field types if necessary
                if (!fieldDescribe.isCalculated() || fieldDescribe.isNillable() || fieldDescribe.isFilterable()) { // Be more selective about calculated fields
                    if (!fieldKey.contains('.')) { 
                         fieldNames.add(fieldDescribe.getName());
                    }
                }
            }
        }
        
        if(fieldNames.isEmpty()){ 
            fieldNames.add('Id');
            if(sObjectFieldMap.containsKey('Name') && sObjectFieldMap.get('Name').getDescribe().isAccessible()){
                 fieldNames.add('Name');
            }
        } else if (!fieldNames.contains('Id')) {
            fieldNames.add('Id'); 
        }

        String soqlQuery = 'SELECT ' + String.join(new List<String>(new Set<String>(fieldNames)), ',') + 
                           ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        
        SObject record;
        try {
            System.debug('Executing main record query: ' + soqlQuery);
            record = Database.query(soqlQuery);
        } catch (Exception e) {
            System.debug('Dynamic query for main record failed: ' + e.getMessage() + '. Falling back to Id, Name.');
            List<String> basicFields = new List<String>{'Id'};
            if(sObjectFieldMap.containsKey('Name') && sObjectFieldMap.get('Name').getDescribe().isAccessible()){
                 basicFields.add('Name');
            }
            soqlQuery = 'SELECT ' + String.join(basicFields, ',') + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
            record = Database.query(soqlQuery);
        }
        
        Map<String, Object> recordMap = new Map<String, Object>();
        for (String field : record.getPopulatedFieldsAsMap().keySet()) {
            recordMap.put(field, record.get(field));
        }
        
        return recordMap;
    }
    
    public static Map<String, Object> getRelatedRecords(String recordId, String objectApiName, Set<String> desiredRelatedObjects) {
        Map<String, Object> relatedRecordsMap = new Map<String, Object>();

        if (String.isBlank(recordId) || String.isBlank(objectApiName)) {
            return relatedRecordsMap;
        }
        
        if (desiredRelatedObjects == null || desiredRelatedObjects.isEmpty()) {
            System.debug('No desired related objects specified or extracted from prompt. Skipping related record fetch.');
            return relatedRecordsMap;
        }
        
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        List<Schema.ChildRelationship> childRelationships = objectDescribe.getChildRelationships();
        
        Integer processedObjectTypesCount = 0;
        Integer maxDesiredObjectTypesToQuery = 5; 

        Set<String> restrictedObjects = new Set<String>{
            'OutgoingEmail', 'EmailMessage', 'ContentDocumentLink', 'NetworkUserHistoryRecent'
        };
        
        Set<String> nonFilterableRelationshipFields = new Set<String>{ 
            'RelatedToId', 'LinkedEntityId' 
        };
        
        for (Schema.ChildRelationship relationship : childRelationships) {
            if (processedObjectTypesCount >= maxDesiredObjectTypesToQuery) {
                System.debug('Reached max desired object types to query (' + maxDesiredObjectTypesToQuery + '). Stopping related record search.');
                break;
            }
            
            Schema.DescribeSObjectResult childObjectDescribe = relationship.getChildSObject().getDescribe();
            String childObjectName = childObjectDescribe.getName();
            Schema.SObjectField childField = relationship.getField(); // This is the field on the child object that links to the parent
            
            if (!desiredRelatedObjects.contains(childObjectName)) {
                continue; 
            }

            String relationshipFieldNameOnChild = childField.getDescribe().getName();
            
            if (childObjectName.endsWith('ChangeEvent') || 
                childObjectName.contains('History') || // Broader match for history objects
                childObjectName.contains('Share') ||   // Broader match for share objects
                !childObjectDescribe.isAccessible() ||
                !childObjectDescribe.isQueryable() ||
                restrictedObjects.contains(childObjectName) ||
                nonFilterableRelationshipFields.contains(relationshipFieldNameOnChild) || 
                !childField.getDescribe().isFilterable()) { 
                System.debug('Skipping relationship: ' + childObjectName + 
                             ' due to restrictions or relationship field ' + relationshipFieldNameOnChild + ' not filterable.');
                continue;
            }
            
            String relatedListLabel = childObjectDescribe.getLabelPlural() != null ? childObjectDescribe.getLabelPlural() : childObjectName; 
            
            try {
                Map<String, Schema.SObjectField> childFieldMap = childObjectDescribe.fields.getMap();
                
                List<String> fieldsToQuery = new List<String>();
                for(String fieldNameKey : childFieldMap.keySet()) {
                    Schema.DescribeFieldResult fieldDesc = childFieldMap.get(fieldNameKey).getDescribe();
                    if(fieldDesc.isAccessible() && 
                       (!fieldDesc.isCalculated() || fieldDesc.isFilterable()) && // Include filterable calculated fields
                       fieldDesc.getSoapType() != Schema.SoapType.ADDRESS && 
                       fieldDesc.getSoapType() != Schema.SoapType.LOCATION &&
                       !fieldNameKey.contains('.')) { 
                        fieldsToQuery.add(fieldDesc.getName());
                    }
                }
                
                if(fieldsToQuery.isEmpty()) {
                    System.debug('No accessible fields found for ' + childObjectName + '. Skipping.');
                    continue;
                }
                 if (!fieldsToQuery.contains('Id')) { 
                    fieldsToQuery.add('Id');
                }
                
                String childSoql = 'SELECT ' + String.join(new List<String>(new Set<String>(fieldsToQuery)), ',') + 
                                   ' FROM ' + childObjectName + 
                                   ' WHERE ' + relationshipFieldNameOnChild + ' = :recordId LIMIT 100'; 
                
                System.debug('Querying related records for ' + childObjectName + ': ' + childSoql);
                List<SObject> relatedSObjects = Database.query(childSoql);
                
                if (!relatedSObjects.isEmpty()) {
                    List<Map<String, Object>> recordsList = new List<Map<String, Object>>();
                    for (SObject relatedRecord : relatedSObjects) {
                        Map<String, Object> recordMap = new Map<String, Object>();
                        for (String fieldKey : relatedRecord.getPopulatedFieldsAsMap().keySet()) {
                            recordMap.put(fieldKey, relatedRecord.get(fieldKey));
                        }
                        recordsList.add(recordMap);
                    }
                    relatedRecordsMap.put(relatedListLabel, recordsList); 
                    processedObjectTypesCount++;
                    System.debug('Successfully queried ' + relatedSObjects.size() + ' ' + childObjectName + 
                                 ' records using relationship field ' + relationshipFieldNameOnChild + '.');
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Error querying related records for ' + childObjectName + 
                             ' using ' + relationshipFieldNameOnChild + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
            }
        }
        
        return relatedRecordsMap;
    }
    
    private static final String ENDPOINT = 'https://ykb08pmg3l.execute-api.ap-south-1.amazonaws.com/default/SF-context-data';
    
    public static HttpResponse callLambdaFunction(String prompt, Map<String, Object> recordContext) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json; charset=utf-8'); 
        
        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('prompt', prompt);
        requestBody.put('recordContext', recordContext);
        
        String serializedBody = JSON.serialize(requestBody);
        System.debug('Request Body for Lambda (first 1000 chars): ' + (serializedBody.length() > 1000 ? serializedBody.substring(0, 1000) + '...' : serializedBody));
        request.setBody(serializedBody);
        request.setTimeout(60000); 
        
        Http http = new Http();
        HttpResponse response;
        
        try {
            response = http.send(request);
            System.debug('Lambda call status: ' + response.getStatusCode() + ' - ' + response.getStatus());
            System.debug('Lambda response body (first 500 chars): ' + (response.getBody() != null ? response.getBody().substring(0, Math.min(response.getBody().length(), 500)) : 'null'));
            return response;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error calling AWS Lambda: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Failed to communicate with the AI service: ' + e.getMessage());
        }
    }
    
   public static String getResponseBody(String prompt, Map<String, Object> recordContext) {
        try {
            HttpResponse response = callLambdaFunction(prompt, recordContext);
            
            if (response.getStatusCode() != 200) {
                System.debug('API request failed. Status: ' + response.getStatus() + ', Code: ' + response.getStatusCode() + ', Body: ' + response.getBody());
                throw new AuraHandledException('AI service request failed: ' + response.getStatus() + ' (Code: ' + response.getStatusCode() + ')');
            }
            
            String responseBody = response.getBody();
            if (String.isBlank(responseBody)) {
                throw new AuraHandledException('AI service returned an empty response.');
            }

            // Corrected deserialization - Fixed the casting issue
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            if (!responseMap.containsKey('data')) {
                 System.debug('Invalid API response structure. "data" key missing. Response: ' + responseBody);
                throw new AuraHandledException('Invalid AI service response structure (missing "data").');
            }
            
            Object dataObject = responseMap.get('data');
            if (!(dataObject instanceof Map<String, Object>)) {
                 System.debug('Invalid API response structure. "data" is not a map. Response: ' + responseBody);
                throw new AuraHandledException('Invalid AI service response structure ("data" not a map).');
            }
            Map<String, Object> data = (Map<String, Object>) dataObject; 
            
            if (!data.containsKey('aiResponse')) {
                System.debug('Invalid API response structure. "aiResponse" key missing in data. Response: ' + responseBody);
                throw new AuraHandledException('Invalid AI service response structure (missing "aiResponse").');
            }

            Object aiResponseObject = data.get('aiResponse');
            if(!(aiResponseObject instanceof String)){
                 System.debug('Invalid API response structure. "aiResponse" is not a String. Response: ' + responseBody);
                throw new AuraHandledException('Invalid AI service response ("aiResponse" not text).');
            }
            String aiResponse = (String) aiResponseObject;

            return aiResponse.replaceAll('\n', ' ').replaceAll('\"', '').trim();
            
        } catch (AuraHandledException e) { 
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error processing AI service response: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Error processing AI response: ' + e.getMessage());
        }
    }
}