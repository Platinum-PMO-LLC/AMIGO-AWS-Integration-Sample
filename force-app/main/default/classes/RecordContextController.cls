public with sharing class RecordContextController {

    // Token limits and configuration
    private static final Integer MAX_TOKEN_LIMIT = 7000; // Leave buffer for response
    private static final Integer MAX_RELATED_RECORDS_PER_OBJECT = 100; // Max number of related records per object type
    private static final Integer MAX_FIELDS_PER_RECORD = 30; // Limit fields per main record
    private static final Integer MAX_RELATED_OBJECT_TYPES = 3; // Max number of related object types to fetch

    @AuraEnabled
    public static Map<String, Object> getRecordContext(String recordId, String prompt) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required');
        }
        
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            String objectApiName = getObjectApiName(recordId);
            System.debug('Object API Name: ' + objectApiName);
            result.put('objectApiName', objectApiName);

            Map<String, Object> recordFields = getRecordFields(recordId, objectApiName, prompt);
            result.put('record', recordFields);

            Set<String> desiredRelatedObjects = extractDesiredObjectsFromPrompt(prompt, objectApiName);
            System.debug('Desired related objects from prompt: ' + JSON.serialize(desiredRelatedObjects));

            Map<String, Object> relatedRecords = getRelatedRecords(recordId, objectApiName, desiredRelatedObjects);
            result.put('relatedRecords', relatedRecords);

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
            Map<String, Object> recordContext = getRecordContext(recordId, prompt);
            
            // Optimize context based on token limits
            Map<String, Object> optimizedContext = optimizeContextForTokens(recordContext, prompt);
            
            String response = getResponseBody(prompt, optimizedContext);

            System.debug('AI response: ' + response);
            
            return response;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in processPrompt: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Error processing prompt: ' + e.getMessage());
        }
    }

    /**
     * Optimizes the record context to fit within token limits.
     * This method prioritizes reducing the number of fields per record and then
     * the number of related records if the token limit is still exceeded.
     */
    private static Map<String, Object> optimizeContextForTokens(Map<String, Object> recordContext, String prompt) {
        String contextJson = JSON.serialize(recordContext);
        Integer estimatedTokens = estimateTokenCount(contextJson + prompt);
        
        System.debug('Estimated tokens before optimization: ' + estimatedTokens);
        
        if (estimatedTokens <= MAX_TOKEN_LIMIT) {
            return recordContext; // No optimization needed
        }
        
        Map<String, Object> optimizedContext = new Map<String, Object>(recordContext);
        
        // Step 1: Optimize fields within the main record based on prompt relevance
        if (optimizedContext.containsKey('record')) {
            Map<String, Object> record = (Map<String, Object>) optimizedContext.get('record');
            Map<String, Object> essentialFields = getEssentialFields(record, prompt);
            optimizedContext.put('record', essentialFields);
        }

        // Step 2: Optimize related records by limiting fields per related record
        // and then potentially truncating the number of related records if still over limit.
        if (optimizedContext.containsKey('relatedRecords')) {
            Map<String, Object> relatedRecords = (Map<String, Object>) optimizedContext.get('relatedRecords');
            
            // This method now focuses on ensuring each related record has only essential fields
            // and respects MAX_RELATED_RECORDS_PER_OBJECT from the query.
            // It no longer applies a hardcoded limit of 5 records per object type here,
            // relying on MAX_RELATED_RECORDS_PER_OBJECT from the SOQL query.
            Map<String, Object> processedRelated = processRelatedRecordsForCompression(relatedRecords);
            optimizedContext.put('relatedRecords', processedRelated);

            // Re-estimate tokens after initial optimization of main record and related record fields
            String currentOptimizedJson = JSON.serialize(optimizedContext);
            Integer currentEstimatedTokens = estimateTokenCount(currentOptimizedJson + prompt);
            System.debug('Estimated tokens after initial field optimization: ' + currentEstimatedTokens);

            // If still over the token limit, then apply more aggressive truncation of related records count
            if (currentEstimatedTokens > MAX_TOKEN_LIMIT) {
                System.debug('Still over token limit, applying aggressive related record truncation.');
                Map<String, Object> aggressivelyTruncatedRelated = truncateRelatedRecordsAggressively(processedRelated);
                optimizedContext.put('relatedRecords', aggressivelyTruncatedRelated);
            }
        }
        
        String optimizedJson = JSON.serialize(optimizedContext);
        Integer finalTokens = estimateTokenCount(optimizedJson + prompt);
        System.debug('Estimated tokens after final optimization: ' + finalTokens);
        
        return optimizedContext;
    }

    /**
     * Estimates token count (rough approximation: 1 token ≈ 4 characters)
     */
    private static Integer estimateTokenCount(String text) {
        return text != null ? (text.length() / 4) : 0;
    }

    /**
     * Processes related records to ensure each record only contains essential fields.
     * This method does NOT truncate the number of related records per object type,
     * it relies on the initial query limit (MAX_RELATED_RECORDS_PER_OBJECT).
     */
    private static Map<String, Object> processRelatedRecordsForCompression(Map<String, Object> relatedRecords) {
        Map<String, Object> processed = new Map<String, Object>();
        
        for (String objectLabel : relatedRecords.keySet()) {
            List<Object> recordsList = (List<Object>) relatedRecords.get(objectLabel);
            List<Object> processedList = new List<Object>();
            
            for (Object recordObj : recordsList) {
                if (recordObj instanceof Map<String, Object>) {
                    Map<String, Object> recordMap = (Map<String, Object>) recordObj;
                    // Apply field reduction to each related record
                    Map<String, Object> essentialRecord = getEssentialFieldsFromRecord(recordMap);
                    processedList.add(essentialRecord);
                }
            }
            
            if (!processedList.isEmpty()) {
                processed.put(objectLabel, processedList);
            }
        }
        
        return processed;
    }

    /**
     * Aggressively truncates the number of related records per object type
     * if the token limit is still exceeded after other optimizations.
     * This is a fallback for severe token constraints.
     */
    private static Map<String, Object> truncateRelatedRecordsAggressively(Map<String, Object> relatedRecords) {
        Map<String, Object> truncated = new Map<String, Object>();
        
        for (String objectLabel : relatedRecords.keySet()) {
            List<Object> recordsList = (List<Object>) relatedRecords.get(objectLabel);
            List<Object> truncatedList = new List<Object>();
            
            // Limit to a very small number of records (e.g., 5) if aggressive truncation is needed
            Integer count = 0;
            for (Object recordObj : recordsList) {
                if (count >= 5) break; 
                truncatedList.add(recordObj); // Add the already field-optimized record
                count++;
            }
            
            if (!truncatedList.isEmpty()) {
                truncated.put(objectLabel, truncatedList);
            }
        }
        
        return truncated;
    }


    /**
     * Gets essential fields based on prompt context and common important fields
     */
    private static Map<String, Object> getEssentialFields(Map<String, Object> record, String prompt) {
        Map<String, Object> essential = new Map<String, Object>();
        
        // Always include these essential fields
        Set<String> alwaysInclude = new Set<String>{'Id', 'Name', 'Status', 'Stage', 'Amount', 'CloseDate', 'Type', 'Priority'};
        
        // Extract fields mentioned in the prompt
        Set<String> promptFields = extractFieldsFromPrompt(prompt);
        
        Set<String> fieldsToInclude = new Set<String>();
        fieldsToInclude.addAll(alwaysInclude);
        fieldsToInclude.addAll(promptFields);
        
        Integer fieldCount = 0;
        for (String fieldName : record.keySet()) {
            if (fieldCount >= MAX_FIELDS_PER_RECORD) break;
            
            String transformedFieldName = transformFieldName(fieldName);
            if (shouldIncludeField(fieldName, transformedFieldName, fieldsToInclude) || 
                record.keySet().size() <= 5) { // If record has few fields, include them all
                essential.put(fieldName, record.get(fieldName));
                fieldCount++;
            }
        }
        
        return essential;
    }

    /**
     * Gets essential fields from a record map (for related records).
     * This method limits the number of fields for each individual related record.
     */
    private static Map<String, Object> getEssentialFieldsFromRecord(Map<String, Object> recordMap) {
        Map<String, Object> essential = new Map<String, Object>();
        
        // Priority order for fields
        List<String> priorityFields = new List<String>{'Id', 'Name', 'Status', 'Stage', 'Amount', 'Subject', 'Type'};
        
        Integer fieldCount = 0;
        // First, add priority fields if they exist
        for (String priority : priorityFields) {
            if (fieldCount >= 5) break; // Limit to 5 fields per related record
            
            for (String fieldName : recordMap.keySet()) {
                if (fieldName.toLowerCase().contains(priority.toLowerCase()) || 
                    transformFieldName(fieldName).toLowerCase().contains(priority.toLowerCase())) {
                    essential.put(fieldName, recordMap.get(fieldName));
                    fieldCount++;
                    break;
                }
            }
        }
        
        // Fill remaining slots with other fields
        for (String fieldName : recordMap.keySet()) {
            if (fieldCount >= 5) break;
            if (!essential.containsKey(fieldName)) {
                essential.put(fieldName, recordMap.get(fieldName));
                fieldCount++;
            }
        }
        
        return essential;
    }

    /**
     * Extracts potential field names from the prompt
     */
    private static Set<String> extractFieldsFromPrompt(String prompt) {
        Set<String> extractedFields = new Set<String>();
        
        if (String.isBlank(prompt)) return extractedFields;
        
        String promptLower = prompt.toLowerCase();
        
        // Common field patterns
        List<String> fieldPatterns = new List<String>{
            'name', 'status', 'stage', 'amount', 'date', 'owner', 'type', 'priority', 
            'description', 'phone', 'email', 'address', 'account', 'contact', 'opportunity'
        };
        
        for (String pattern : fieldPatterns) {
            if (promptLower.contains(pattern)) {
                extractedFields.add(pattern);
            }
        }
        
        return extractedFields;
    }

    /**
     * Determines if a field should be included based on importance
     */
    private static Boolean shouldIncludeField(String fieldName, String transformedName, Set<String> importantFields) {
        String fieldLower = fieldName.toLowerCase();
        String transformedLower = transformedName.toLowerCase();
        
        for (String important : importantFields) {
            if (fieldLower.contains(important.toLowerCase()) || 
                transformedLower.contains(important.toLowerCase())) {
                return true;
            }
        }
        
        return false;
    }
    
    private static Set<String> extractDesiredObjectsFromPrompt(String prompt, String parentObjectApiName) {
        Set<String> desiredObjects = new Set<String>();
        if (String.isBlank(prompt) || String.isBlank(parentObjectApiName)) {
            return desiredObjects;
        }

        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectApiName);
        if (parentType == null) {
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
            
            Boolean found = false;

            // Check API name
            if (promptLowerCase.contains(childApiName.toLowerCase())) {
                desiredObjects.add(childApiName);
                found = true;
            }
            
            // Check labels
            if (!found && String.isNotBlank(childLabel)) {
                String labelRegex = '\\b' + Pattern.quote(childLabel.toLowerCase()) + '\\b';
                Pattern labelPattern = Pattern.compile(labelRegex);
                Matcher labelMatcher = labelPattern.matcher(promptLowerCase);
                if (labelMatcher.find()) {
                    desiredObjects.add(childApiName);
                    found = true;
                }
            }
            
            if (!found && String.isNotBlank(childLabelPlural)) {
                String labelPluralRegex = '\\b' + Pattern.quote(childLabelPlural.toLowerCase()) + '\\b';
                Pattern labelPluralPattern = Pattern.compile(labelPluralRegex);
                Matcher labelPluralMatcher = labelPluralPattern.matcher(promptLowerCase);
                if (labelPluralMatcher.find()) {
                    desiredObjects.add(childApiName);
                    found = true;
                }
            }

            // Break if we have enough objects
            if (desiredObjects.size() >= MAX_RELATED_OBJECT_TYPES) {
                break;
            }
        }
        
        return desiredObjects;
    }

    public static String getObjectApiName(Id recordId) {
        return recordId.getSobjectType().getDescribe().getName();
    }
    
    private static String transformFieldName(String apiName) {
        if (String.isBlank(apiName)) {
            return apiName;
        }
        
        String transformed = apiName;
        
        if (transformed.contains('__') && transformed.indexOf('__') < transformed.lastIndexOf('__')) {
            transformed = transformed.substring(transformed.indexOf('__') + 2);
        }
        
        if (transformed.endsWith('__c')) {
            transformed = transformed.substring(0, transformed.length() - 3);
        }
        
        transformed = transformed.replace('_', ' ');
        
        List<String> words = transformed.split(' ');
        List<String> titleCaseWords = new List<String>();
        for (String word : words) {
            if (String.isNotBlank(word)) {
                titleCaseWords.add(word.substring(0, 1).toUpperCase() + 
                                   (word.length() > 1 ? word.substring(1).toLowerCase() : ''));
            }
        }
        
        return String.join(titleCaseWords, ' ');
    }
    
    private static Map<String, Object> transformRecordFieldNames(Map<String, Object> record) {
        Map<String, Object> transformedRecord = new Map<String, Object>();
        
        for (String fieldName : record.keySet()) {
            String transformedFieldName = transformFieldName(fieldName);
            transformedRecord.put(transformedFieldName, record.get(fieldName));
        }
        
        return transformedRecord;
    }
    
    private static Map<String, Object> transformRecordContext(Map<String, Object> recordContext) {
        Map<String, Object> transformedContext = new Map<String, Object>();
        
        if (recordContext.containsKey('record')) {
            Map<String, Object> record = (Map<String, Object>) recordContext.get('record');
            transformedContext.put('record', transformRecordFieldNames(record));
        }
        
        if (recordContext.containsKey('relatedRecords')) {
            Map<String, Object> relatedRecords = (Map<String, Object>) recordContext.get('relatedRecords');
            Map<String, Object> transformedRelatedRecords = new Map<String, Object>();
            
            for (String objectLabel : relatedRecords.keySet()) {
                List<Object> recordsList = (List<Object>) relatedRecords.get(objectLabel);
                List<Object> transformedRecordsList = new List<Object>();
                
                for (Object recordObj : recordsList) {
                    if (recordObj instanceof Map<String, Object>) {
                        Map<String, Object> recordMap = (Map<String, Object>) recordObj;
                        transformedRecordsList.add(transformRecordFieldNames(recordMap));
                    } else {
                        transformedRecordsList.add(recordObj);
                    }
                }
                
                transformedRelatedRecords.put(objectLabel, transformedRecordsList);
            }
            
            transformedContext.put('relatedRecords', transformedRelatedRecords);
        }
        
        for (String key : recordContext.keySet()) {
            if (key != 'record' && key != 'relatedRecords') {
                transformedContext.put(key, recordContext.get(key));
            }
        }
        
        return transformedContext;
    }
    
    private static Map<String, Object> getRecordFields(String recordId, String objectApiName, String prompt) {
        if (String.isBlank(recordId) || String.isBlank(objectApiName)) return new Map<String, Object>();
        
        Map<String, Schema.SObjectField> sObjectFieldMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>();
        
        // Get fields mentioned in prompt
        Set<String> promptFields = extractFieldsFromPrompt(prompt);
        
        for(String fieldKey : sObjectFieldMap.keySet()){
            Schema.DescribeFieldResult fieldDescribe = sObjectFieldMap.get(fieldKey).getDescribe();
            
            if(fieldDescribe.isAccessible() && 
               fieldDescribe.getSoapType() != Schema.SoapType.ADDRESS && 
               fieldDescribe.getSoapType() != Schema.SoapType.LOCATION &&
               !fieldKey.contains('.')) {
                
                // Prioritize fields mentioned in prompt or common important fields
                String fieldName = fieldDescribe.getName();
                if (isImportantField(fieldName, promptFields) || fieldNames.size() < MAX_FIELDS_PER_RECORD) {
                    fieldNames.add(fieldName);
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
            record = Database.query(soqlQuery);
        } catch (Exception e) {
            List<String> basicFields = new List<String>{'Id'};
            if(sObjectFieldMap.containsKey('Name')){
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

    private static Boolean isImportantField(String fieldName, Set<String> promptFields) {
        String fieldLower = fieldName.toLowerCase();
        
        // Always important fields
        if (fieldLower.contains('name') || fieldLower.contains('status') || 
            fieldLower.contains('stage') || fieldLower.contains('amount') ||
            fieldLower.contains('date') || fieldLower.contains('owner')) {
            return true;
        }
        
        // Check against prompt fields
        for (String promptField : promptFields) {
            if (fieldLower.contains(promptField.toLowerCase())) {
                return true;
            }
        }
        
        return false;
    }
    
    public static Map<String, Object> getRelatedRecords(String recordId, String objectApiName, Set<String> desiredRelatedObjects) {
        Map<String, Object> relatedRecordsMap = new Map<String, Object>();

        if (String.isBlank(recordId) || String.isBlank(objectApiName)) {
            return relatedRecordsMap;
        }
        
        if (desiredRelatedObjects == null || desiredRelatedObjects.isEmpty()) {
            return relatedRecordsMap;
        }
        
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        List<Schema.ChildRelationship> childRelationships = objectDescribe.getChildRelationships();
        
        Integer processedObjectTypesCount = 0;

        Set<String> restrictedObjects = new Set<String>{
            'OutgoingEmail', 'EmailMessage', 'ContentDocumentLink', 'NetworkUserHistoryRecent'
        };
        
        for (Schema.ChildRelationship relationship : childRelationships) {
            if (processedObjectTypesCount >= MAX_RELATED_OBJECT_TYPES) {
                break;
            }
            
            Schema.DescribeSObjectResult childObjectDescribe = relationship.getChildSObject().getDescribe();
            String childObjectName = childObjectDescribe.getName();
            Schema.SObjectField childField = relationship.getField();
            
            if (!desiredRelatedObjects.contains(childObjectName)) {
                continue; 
            }

            String relationshipFieldNameOnChild = childField.getDescribe().getName();
            
            if (childObjectName.endsWith('ChangeEvent') || 
                childObjectName.contains('History') || 
                childObjectName.contains('Share') ||  
                !childObjectDescribe.isAccessible() ||
                !childObjectDescribe.isQueryable() ||
                restrictedObjects.contains(childObjectName) ||
                !childField.getDescribe().isFilterable()) { 
                continue;
            }
            
            String relatedListLabel = childObjectDescribe.getLabelPlural() != null ? childObjectDescribe.getLabelPlural() : childObjectName; 
            
            try {
                Map<String, Schema.SObjectField> childFieldMap = childObjectDescribe.fields.getMap();
                
                // Get all accessible non-system generated fields for related records
                List<String> fieldsToQuery = getAllNonSystemFieldsForQuery(childFieldMap);
                
                if(fieldsToQuery.isEmpty()) {
                    continue;
                }
                
                if (!fieldsToQuery.contains('Id')) { 
                    fieldsToQuery.add('Id');
                }
                
                String childSoql = 'SELECT ' + String.join(new List<String>(new Set<String>(fieldsToQuery)), ',') + 
                                   ' FROM ' + childObjectName + 
                                   ' WHERE ' + relationshipFieldNameOnChild + ' = :recordId LIMIT ' + MAX_RELATED_RECORDS_PER_OBJECT; 
                
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
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Error querying related records for ' + childObjectName + ': ' + e.getMessage());
            }
        }
        
        return relatedRecordsMap;
    }

    /**
     * Gets all accessible fields for a query, excluding system-generated fields.
     * This method is used for the initial fetch of related records.
     */
    private static List<String> getAllNonSystemFieldsForQuery(Map<String, Schema.SObjectField> fieldMap) {
        List<String> allFields = new List<String>();
        Set<String> systemFieldsToExclude = new Set<String>{
            'CreatedDate', 'LastModifiedDate', 'IsDeleted', 'SystemModstamp', 'OwnerId', 'LastActivityDate',
            'LastViewedDate', 'LastReferencedDate', 'IsArchived', 'MasterRecordId', 'RecordTypeId'
        }; // Add more system fields as needed

        for (String fieldKey : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldKey).getDescribe();
            String fieldName = fieldDesc.getName();

            // Exclude system fields and inaccessible fields
            if (fieldDesc.isAccessible() && 
                !systemFieldsToExclude.contains(fieldName) &&
                !fieldName.endsWith('__r') && // Exclude relationship fields (parent relationships)
                !fieldName.contains('.') && // Exclude polymorphic fields like Owner.Name
                fieldDesc.getSoapType() != Schema.SoapType.ADDRESS && 
                fieldDesc.getSoapType() != Schema.SoapType.LOCATION) {
                allFields.add(fieldName);
            }
        }
        
        // Ensure 'Id' is always included if not already present
        if (!allFields.contains('Id')) {
            allFields.add('Id');
        }
        
        // Ensure 'Name' is always included if available and not already present
        if (fieldMap.containsKey('Name') && fieldMap.get('Name').getDescribe().isAccessible() && !allFields.contains('Name')) {
            allFields.add('Name');
        }

        return allFields;
    }
    
    private static final String ENDPOINT = 'https://ykb08pmg3l.execute-api.ap-south-1.amazonaws.com/default/SF-context-data';
    
    public static HttpResponse callLambdaFunction(String prompt, Map<String, Object> recordContext) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json; charset=utf-8'); 
        
        Map<String, Object> transformedRecordContext = transformRecordContext(recordContext);
        
        Map<String, Object> requestBody = new Map<String, Object>();
        // Simplified system prompt to save tokens
        String systemPrompt = 'Analyze this Salesforce record and answer the user query:\n' + JSON.serialize(transformedRecordContext);
        requestBody.put('prompt', systemPrompt + '\n\nQuery: ' + prompt);
        requestBody.put('recordContext', transformedRecordContext);
        
        String serializedBody = JSON.serialize(requestBody);
        request.setBody(serializedBody);
        request.setTimeout(60000); 
        
        Http http = new Http();
        HttpResponse response;
        
        try {
            response = http.send(request);
            return response;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error calling AWS Lambda: ' + e.getMessage());
            throw new AuraHandledException('Failed to communicate with the AI service: ' + e.getMessage());
        }
    }
    
    public static String getResponseBody(String prompt, Map<String, Object> recordContext) {
        try {
            HttpResponse response = callLambdaFunction(prompt, recordContext);
            
            if (response.getStatusCode() != 200) {
                throw new AuraHandledException('AI service request failed: ' + response.getStatus());
            }
            
            String responseBody = response.getBody();
            if (String.isBlank(responseBody)) {
                throw new AuraHandledException('AI service returned an empty response.');
            }

            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            if (!responseMap.containsKey('data')) {
                throw new AuraHandledException('Invalid AI service response structure.');
            }
            
            Map<String, Object> data = (Map<String, Object>) responseMap.get('data');
            
            if (!data.containsKey('aiResponse')) {
                throw new AuraHandledException('Invalid AI service response structure.');
            }

            String aiResponse = (String) data.get('aiResponse');
            
            return aiResponse.replaceAll('\n', ' ').replaceAll('\"', '').trim();
            
        } catch (AuraHandledException e) { 
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error processing AI service response: ' + e.getMessage());
            throw new AuraHandledException('Error processing AI response: ' + e.getMessage());
        }
    }
}
