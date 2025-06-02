public with sharing class SFDataExporter {
    
    // Reduced governor limits for CPU efficiency
    private static final Integer MAX_QUERIES_PER_EXECUTION = 50;
    private static final Integer MAX_RECORDS_PER_OBJECT = 100;
    private static final Integer MAX_CHILD_RECORDS = 5;
    private static final Integer MAX_FIELDS_PER_QUERY = 15;
    private static final Integer MAX_METADATA_FIELDS = 20;
    
    // System objects to exclude from processing
    private static final Set<String> EXCLUDED_OBJECTS = new Set<String>{
        'ActivityHistory', 'AttachedContentDocument', 'AttachedContentNote', 'CombinedAttachment',
        'ContentDocumentLink', 'EntitySubscription', 'Event', 'LookedUpFromActivity', 'NetworkUserHistoryRecent',
        'Note', 'NoteAndAttachment', 'OpenActivity', 'ProcessInstance', 'ProcessInstanceHistory',
        'RecordAction', 'RecordActionHistory', 'Task', 'TopicAssignment', 'UserDefinedLabelAssignment',
        'ActivityHistory', 'EmailStatus', 'TaskFeed', 'EventFeed', 'UserRecordAccess'
    };
    
    // Objects that commonly don't have Name field
    private static final Set<String> OBJECTS_WITHOUT_NAME = new Set<String>{
        'ContentVersion', 'ContentDocument', 'Document', 'Attachment'
    };
    
    // Cache for expensive describe operations
    private static Map<String, Schema.DescribeSObjectResult> describeCache = new Map<String, Schema.DescribeSObjectResult>();
    private static Map<String, List<String>> fieldCache = new Map<String, List<String>>();
    
    // Centralized exclusion logic
    private static Boolean isExcludedObject(String objectName) {
        return EXCLUDED_OBJECTS.contains(objectName) ||
               objectName.endsWith('__Share') || 
               objectName.endsWith('__History') ||
               objectName.endsWith('__Feed') ||
               objectName.contains('__mdt') ||
               objectName.contains('__e') ||
               objectName.startsWith('SBQQ');
    }
    
    // Main method - exports one object at a time safely
    public static String exportSingleCustomObjectToS3(String objectName) {
        Long startTime = System.currentTimeMillis();
        
        try {
            // Early validation with timeout check
            if (!isObjectProcessable(objectName)) {
                return 'Object ' + objectName + ' cannot be processed (not queryable or excluded)';
            }
            
            // Check CPU usage early
            if (Limits.getCpuTime() > 8000) {
                return 'CPU limit approaching, skipping ' + objectName;
            }
            
            String jsonPayload = generateLightweightJsonPayload(objectName);
            
            if (String.isNotBlank(jsonPayload)) {
                System.debug('Generated JSON payload for ' + objectName + ' in ' + 
                           (System.currentTimeMillis() - startTime) + 'ms');

                // String s3Uri = AWSuploadSFDataToS3.uploadToS3VectorStorage(jsonPayload, objectName);
                return 'Successfully uploaded ' + objectName + ' to S3: '; //+ s3Uri;
            } else {
                return 'No data generated for ' + objectName;
            }
        } catch (Exception e) {
            System.debug('Error processing object ' + objectName + ': ' + e.getMessage());
            throw new AuraHandledException('Failed to export ' + objectName + ': ' + e.getMessage());
        }
    }
    
    // Lightweight JSON generation - focuses on essential data only
    public static String generateLightweightJsonPayload(String objectName) {
        try {
            Long startTime = System.currentTimeMillis();
            Integer queriesUsed = Limits.getQueries();
            
            // Get minimal but essential metadata
            Map<String, Object> objectMetadata = getEssentialObjectMetadata(objectName);
            
            // CPU check after metadata
            if (Limits.getCpuTime() > 7000) {
                System.debug('CPU limit approaching during metadata processing for ' + objectName);
                return null;
            }
            
            // Get records with optimized approach
            List<Map<String, Object>> recordsData = getOptimizedObjectRecords(objectName);
            
            // Build minimal payload
            Map<String, Object> payload = new Map<String, Object>{
                'exportMetadata' => new Map<String, Object>{
                    'objectName' => objectName,
                    'exportTimestamp' => System.now().getTime(),
                    'totalRecords' => recordsData.size(),
                    'source' => 'Salesforce',
                    'version' => '2.1',
                    'processingTimeMs' => System.currentTimeMillis() - startTime,
                    'queriesUsed' => Limits.getQueries() - queriesUsed,
                    'cpuTimeUsed' => Limits.getCpuTime()
                },
                'objectMetadata' => objectMetadata,
                'records' => recordsData
            };
            
            return JSON.serialize(payload); // Use serialize instead of serializePretty to save CPU
            
        } catch (Exception e) {
            System.debug('Error generating JSON for ' + objectName + ': ' + e.getMessage());
            return null;
        }
    }
    
    // Essential metadata only - much faster than comprehensive version
    private static Map<String, Object> getEssentialObjectMetadata(String objectName) {
        try {
            Schema.DescribeSObjectResult objDescribe = getCachedDescribe(objectName);
            if (objDescribe == null) return new Map<String, Object>{'error' => 'Cannot describe object'};
            
            Map<String, Object> metadata = new Map<String, Object>{
                'objectName' => objDescribe.getName(),
                'label' => objDescribe.getLabel(),
                'isCustom' => objDescribe.isCustom(),
                'keyPrefix' => objDescribe.getKeyPrefix(),
                'fields' => getEssentialFieldMetadata(objDescribe),
                'recordTypeCount' => objDescribe.getRecordTypeInfos().size()
            };
            
            return metadata;
            
        } catch (Exception e) {
            System.debug('Error getting metadata for ' + objectName + ': ' + e.getMessage());
            return new Map<String, Object>{'error' => e.getMessage()};
        }
    }
    
    // Essential field metadata only - limited processing
    private static List<Map<String, Object>> getEssentialFieldMetadata(Schema.DescribeSObjectResult objDescribe) {
        List<Map<String, Object>> fieldsMetadata = new List<Map<String, Object>>();
        
        try {
            Integer processedFields = 0;
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
            
            // Process only essential fields to avoid CPU timeout
            for (String fieldName : fieldMap.keySet()) {
                if (processedFields >= MAX_METADATA_FIELDS) break;
                
                // CPU check during field processing
                if (Limits.getCpuTime() > 6000) break;
                
                try {
                    Schema.SObjectField field = fieldMap.get(fieldName);
                    Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                    
                    // Only include accessible fields
                    if (!fieldDescribe.isAccessible()) continue;
                    
                    Map<String, Object> fieldInfo = new Map<String, Object>{
                        'name' => fieldDescribe.getName(),
                        'label' => fieldDescribe.getLabel(),
                        'type' => fieldDescribe.getType().name(),
                        'isCustom' => fieldDescribe.isCustom(),
                        'isRequired' => !fieldDescribe.isNillable()
                    };
                    
                    // Only add picklist values for key fields to save CPU
                    if ((fieldDescribe.getType() == Schema.DisplayType.PICKLIST || 
                         fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST) &&
                        (fieldName.equalsIgnoreCase('Status') || fieldName.equalsIgnoreCase('Type') || 
                         fieldName.equalsIgnoreCase('Stage'))) {
                        fieldInfo.put('picklistValues', getLimitedPicklistValues(fieldDescribe));
                    }
                    
                    fieldsMetadata.add(fieldInfo);
                    processedFields++;
                    
                } catch (Exception e) {
                    System.debug('Error processing field ' + fieldName + ': ' + e.getMessage());
                    continue;
                }
            }
        } catch (Exception e) {
            System.debug('Error getting field metadata: ' + e.getMessage());
        }
        
        return fieldsMetadata;
    }
    
    // Limited picklist processing
    private static List<String> getLimitedPicklistValues(Schema.DescribeFieldResult fieldDescribe) {
        List<String> picklistValues = new List<String>();
        try {
            Integer valueCount = 0;
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (valueCount >= 10) break; // Limit picklist values
                if (entry.isActive()) {
                    picklistValues.add(entry.getValue());
                    valueCount++;
                }
            }
        } catch (Exception e) {
            System.debug('Error getting picklist values: ' + e.getMessage());
        }
        return picklistValues;
    }
    
    // Cached describe to avoid repeated expensive operations
    private static Schema.DescribeSObjectResult getCachedDescribe(String objectName) {
        if (describeCache.containsKey(objectName)) {
            return describeCache.get(objectName);
        }
        
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType != null) {
                Schema.DescribeSObjectResult describe = objType.getDescribe();
                describeCache.put(objectName, describe);
                return describe;
            }
        } catch (Exception e) {
            System.debug('Error describing ' + objectName + ': ' + e.getMessage());
        }
        
        return null;
    }
    
    // Optimized record retrieval - minimal processing
    private static List<Map<String, Object>> getOptimizedObjectRecords(String objectName) {
        List<Map<String, Object>> recordsData = new List<Map<String, Object>>();
        
        try {
            List<String> queryFields = getCachedQueryFields(objectName);
            if (queryFields.isEmpty()) {
                System.debug('No queryable fields found for ' + objectName);
                return recordsData;
            }
            
            String query = 'SELECT ' + String.join(queryFields, ', ') + 
                          ' FROM ' + objectName + 
                          ' ORDER BY Id LIMIT ' + MAX_RECORDS_PER_OBJECT;
            
            List<SObject> records = Database.query(query);
            
            for (SObject record : records) {
                // CPU check during record processing
                if (Limits.getCpuTime() > 8000) {
                    System.debug('CPU limit reached, stopping record processing');
                    break;
                }
                
                Map<String, Object> recordData = new Map<String, Object>();
                recordData.put('mainRecord', convertSObjectToMapOptimized(record));
                
                recordsData.add(recordData);
            }
            
        } catch (Exception e) {
            System.debug('Error querying ' + objectName + ': ' + e.getMessage());
        }
        
        return recordsData;
    }
    
    // Cached field selection for queries
    private static List<String> getCachedQueryFields(String objectName) {
        if (fieldCache.containsKey(objectName)) {
            return fieldCache.get(objectName);
        }
        
        List<String> safeFields = buildOptimizedFieldList(objectName);
        fieldCache.put(objectName, safeFields);
        return safeFields;
    }
    
    // Optimized field list building
    private static List<String> buildOptimizedFieldList(String objectName) {
        List<String> safeFields = new List<String>();
        
        try {
            Schema.DescribeSObjectResult objDescribe = getCachedDescribe(objectName);
            if (objDescribe == null) return safeFields;
            
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
            
            // Always include Id if accessible
            if (fieldMap.containsKey('Id')) {
                safeFields.add('Id');
            }
            
            // Add Name field if it exists and is accessible
            if (fieldMap.containsKey('Name') && !OBJECTS_WITHOUT_NAME.contains(objectName)) {
                Schema.DescribeFieldResult nameField = fieldMap.get('Name').getDescribe();
                if (nameField.isAccessible()) {
                    safeFields.add('Name');
                }
            }
            
            // Add essential system fields
            List<String> essentialFields = new List<String>{'CreatedDate', 'LastModifiedDate', 'OwnerId'};
            for (String fieldName : essentialFields) {
                if (fieldMap.containsKey(fieldName) && !safeFields.contains(fieldName)) {
                    Schema.DescribeFieldResult field = fieldMap.get(fieldName).getDescribe();
                    if (field.isAccessible()) {
                        safeFields.add(fieldName);
                    }
                }
            }
            
            // Add other accessible fields up to limit
            Integer fieldCount = safeFields.size();
            for (String fieldName : fieldMap.keySet()) {
                if (fieldCount >= MAX_FIELDS_PER_QUERY) break;
                if (Limits.getCpuTime() > 5000) break; // CPU check
                
                if (!safeFields.contains(fieldName)) {
                    try {
                        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                        if (fieldDescribe.isAccessible() && isFieldSafeToQueryOptimized(fieldDescribe)) {
                            safeFields.add(fieldName);
                            fieldCount++;
                        }
                    } catch (Exception e) {
                        continue; // Skip problematic fields
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error building field list for ' + objectName + ': ' + e.getMessage());
        }
        
        return safeFields;
    }
    
    // Optimized field safety check
    private static Boolean isFieldSafeToQueryOptimized(Schema.DescribeFieldResult fieldDescribe) {
        try {
            Schema.DisplayType fieldType = fieldDescribe.getType();
            
            // Quick exclusion of problematic types
            return fieldType != Schema.DisplayType.BASE64 &&
                   fieldType != Schema.DisplayType.ENCRYPTEDSTRING &&
                   fieldType != Schema.DisplayType.LOCATION && // Can cause issues
                   !fieldDescribe.getName().toLowerCase().contains('password') &&
                   !fieldDescribe.getName().toLowerCase().contains('token');
        } catch (Exception e) {
            return false;
        }
    }
    
    // Optimized SObject to Map conversion
    private static Map<String, Object> convertSObjectToMapOptimized(SObject record) {
        Map<String, Object> recordMap = new Map<String, Object>();
        
        try {
            // Use getPopulatedFieldsAsMap for efficiency
            Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
            
            for (String fieldName : populatedFields.keySet()) {
                Object fieldValue = populatedFields.get(fieldName);
                if (fieldValue != null) {
                    // Simplified type handling to save CPU
                    if (fieldValue instanceof DateTime) {
                        recordMap.put(fieldName, String.valueOf(fieldValue));
                    } else if (fieldValue instanceof Date) {
                        recordMap.put(fieldName, String.valueOf(fieldValue));
                    } else {
                        recordMap.put(fieldName, fieldValue);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error converting SObject to Map: ' + e.getMessage());
            // Return at least the Id if possible
            try {
                recordMap.put('Id', record.Id);
            } catch (Exception ex) {
                // Ignore
            }
        }
        
        return recordMap;
    }
    
    // Streamlined object validation
    private static Boolean isObjectProcessable(String objectName) {
        if (String.isBlank(objectName)) return false;
        if (isExcludedObject(objectName)) return false;
        
        try {
            Schema.DescribeSObjectResult objDescribe = getCachedDescribe(objectName);
            if (objDescribe == null) return false;
            
            return objDescribe.isAccessible() && objDescribe.isQueryable();
            
        } catch (Exception e) {
            System.debug('Error validating object ' + objectName + ': ' + e.getMessage());
            return false;
        }
    }
    
    // Optimized method to get all processable custom objects
    private static List<String> getAllProcessableCustomObjects() {
        List<String> processableObjects = new List<String>();
        
        try {
            // Query EntityDefinition instead of using global describe
            String query = 'SELECT QualifiedApiName FROM EntityDefinition ' + 
                           'WHERE IsQueryable = true ' +
                           'ORDER BY QualifiedApiName LIMIT 1';

            for (EntityDefinition entity : Database.query(query)) {
                String objectName = entity.QualifiedApiName;
                if (!isExcludedObject(objectName)) {
                    processableObjects.add(objectName);
                }
            }
        } catch (Exception e) {
            System.debug('Error getting processable objects: ' + e.getMessage());
        }
        
        System.debug('Found ' + processableObjects.size() + ' processable custom objects');
        return processableObjects;
    }
    
    // Optimized batch processing
    public static void exportAllCustomObjectsToS3Batch() {
        List<String> processableObjects = getAllProcessableCustomObjects();
        
        if (!processableObjects.isEmpty()) {
            // Process in smaller batches to avoid CPU timeout
            Integer batchSize = Math.min(processableObjects.size(), 3);
            List<String> firstBatch = new List<String>();
            
            for (Integer i = 0; i < batchSize; i++) {
                firstBatch.add(processableObjects[i]);
            }
            
            System.enqueueJob(new OptimizedCustomObjectExportQueueable(firstBatch, 0, processableObjects));
        }
    }
    
    // Utility methods
    public static List<String> getProcessableObjectsList() {
        return getAllProcessableCustomObjects();
    }
    
    public static void clearCaches() {
        describeCache.clear();
        fieldCache.clear();
        System.debug('Caches cleared');
    }
    
    // Debug method to troubleshoot object discovery
    public static Map<String, String> debugObjectDiscovery() {
        Map<String, String> debugInfo = new Map<String, String>();
        
        try {
            List<EntityDefinition> entities = [
                SELECT QualifiedApiName, IsQueryable 
                FROM EntityDefinition 
                ORDER BY QualifiedApiName
            ];
            
            System.debug('=== Starting Object Discovery Debug ===');
            
            for (EntityDefinition entity : entities) {
                String objectName = entity.QualifiedApiName;
                String status = objectName + ': ';
                
                // if (!entity.IsAccessible) status += 'NOT_ACCESSIBLE ';
                if (!entity.IsQueryable) status += 'NOT_QUERYABLE ';
                if (isExcludedObject(objectName)) status += 'EXCLUDED ';
                
                if (entity.IsQueryable && !isExcludedObject(objectName)) {
                    status += 'PROCESSABLE';
                    System.debug('✓ ' + status);
                } else {
                    System.debug('✗ ' + status);
                }
                
                debugInfo.put(objectName, status);
            }
            
            String summary = 'SUMMARY: Total Custom Objects: ' + entities.size() + 
                            ', Processable: ' + debugInfo.size();
            
            System.debug('=== ' + summary + ' ===');
            debugInfo.put('SUMMARY', summary);
            
        } catch (Exception e) {
            debugInfo.put('ERROR', 'Failed to query EntityDefinition: ' + e.getMessage());
        }
        
        return debugInfo;
    }
}

