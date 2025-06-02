public class S3CustomObjectExportQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<String> objectTypes;
    private Integer currentIndex;
    private String lambdaEndpoint;
    private String s3BucketName;
    private Map<String, Object> exportMetadata;
    
    // Constructor for initial call
    public S3CustomObjectExportQueueable(List<String> objectTypes, String lambdaEndpoint, String s3BucketName) {
        this.objectTypes = objectTypes;
        this.currentIndex = 0;
        this.lambdaEndpoint = lambdaEndpoint;
        this.s3BucketName = s3BucketName;
        this.exportMetadata = new Map<String, Object>{
            'exportStartTime' => System.now(),
            'totalObjects' => objectTypes.size(),
            'exportedBy' => UserInfo.getUserId(),
            'orgId' => UserInfo.getOrganizationId()
        };
    }
    
    // Constructor for chaining calls
    private S3CustomObjectExportQueueable(List<String> objectTypes, Integer currentIndex, 
                                         String lambdaEndpoint, String s3BucketName, 
                                         Map<String, Object> exportMetadata) {
        this.objectTypes = objectTypes;
        this.currentIndex = currentIndex;
        this.lambdaEndpoint = lambdaEndpoint;
        this.s3BucketName = s3BucketName;
        this.exportMetadata = exportMetadata;
    }
    
    public void execute(QueueableContext context) {
        try {
            if (currentIndex >= objectTypes.size()) {
                // All objects processed, create summary file
                createExportSummary();
                return;
            }
            
            String objectType = objectTypes[currentIndex];
            System.debug('Processing object type: ' + objectType);
            
            // Export current object
            exportObjectToS3(objectType);
            
            // Chain next object if more exist
            if (currentIndex + 1 < objectTypes.size()) {
                S3CustomObjectExportQueueable nextJob = new S3CustomObjectExportQueueable(
                    objectTypes, 
                    currentIndex + 1, 
                    lambdaEndpoint, 
                    s3BucketName,
                    exportMetadata
                );
                System.enqueueJob(nextJob);
            } else {
                // This was the last object, create summary
                createExportSummary();
            }
            
        } catch (Exception e) {
            System.debug('Error in S3CustomObjectExportQueueable: ' + e.getMessage());
            // Log error and continue with next object
            logError(objectTypes[currentIndex], e);
            
            // Continue with next object even if current one failed
            if (currentIndex + 1 < objectTypes.size()) {
                S3CustomObjectExportQueueable nextJob = new S3CustomObjectExportQueueable(
                    objectTypes, 
                    currentIndex + 1, 
                    lambdaEndpoint, 
                    s3BucketName,
                    exportMetadata
                );
                System.enqueueJob(nextJob);
            }
        }
    }
    
    private void exportObjectToS3(String objectType) {
        try {
            // Generate filename
            String fileName = objectType + '_' + System.now().getTime() + '.json';
            String s3Path = 'salesforce-exports/' + fileName;
            
            // Get object data with related records
            Map<String, Object> objectData = getObjectDataWithRelated(objectType);
            
            // Prepare metadata
            Map<String, String> metadata = new Map<String, String>{
                'objectType' => objectType,
                'exportTime' => String.valueOf(System.now()),
                'recordCount' => String.valueOf(objectData.get('recordCount')),
                'salesforceOrg' => UserInfo.getOrganizationId(),
                'exportedBy' => UserInfo.getUserId()
            };
            
            // Prepare request payload for Lambda
            Map<String, Object> payload = new Map<String, Object>{
                's3Bucket' => s3BucketName,
                's3Key' => s3Path,
                'content' => JSON.serialize(objectData),
                'metadata' => metadata
            };
            
            // Send to Lambda
            HttpRequest req = new HttpRequest();
            req.setEndpoint(lambdaEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(120000); // 2 minutes timeout
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                System.debug('Successfully exported ' + objectType + ' to S3: ' + s3Path);
                
                // Parse response to get S3 details
                Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                // Log success
                logSuccess(objectType, s3Path, (String)responseData.get('etag'), fileName);
                
            } else {
                System.debug('Failed to export ' + objectType + '. Status: ' + res.getStatusCode() + ', Body: ' + res.getBody());
                throw new CalloutException('Lambda returned status: ' + res.getStatusCode() + ', Response: ' + res.getBody());
            }
            
        } catch (Exception e) {
            System.debug('Error exporting ' + objectType + ': ' + e.getMessage());
            throw e;
        }
    }
    
    private Map<String, Object> getObjectDataWithRelated(String objectType) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Get object describe
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectType);
            if (sObjectType == null) {
                throw new QueryException('Object type not found: ' + objectType);
            }
            
            Schema.DescribeSObjectResult objectDescribe = sObjectType.getDescribe();
            
            // Build dynamic SOQL query for main object
            Set<String> fieldNames = new Set<String>();
            Map<String, Schema.SObjectField> fieldsMap = objectDescribe.fields.getMap();
            
            for (String fieldName : fieldsMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
                if (fieldDescribe.isAccessible()) {
                    fieldNames.add(fieldName);
                }
            }
            
            String soqlQuery = 'SELECT ' + String.join(new List<String>(fieldNames), ', ') + 
                              ' FROM ' + objectType + 
                              ' ORDER BY CreatedDate DESC LIMIT 1000'; // Limit to prevent timeout
            
            List<SObject> records = Database.query(soqlQuery);
            
            // Convert records to serializable format
            List<Map<String, Object>> serializedRecords = new List<Map<String, Object>>();
            
            for (SObject record : records) {
                Map<String, Object> recordMap = new Map<String, Object>();
                
                // Add main object fields
                for (String fieldName : fieldNames) {
                    Object fieldValue = record.get(fieldName);
                    recordMap.put(fieldName, fieldValue);
                }
                
                // Get related records (child relationships)
                Map<String, List<Map<String, Object>>> relatedRecords = getRelatedRecords(record.Id, objectDescribe);
                if (!relatedRecords.isEmpty()) {
                    recordMap.put('RelatedRecords', relatedRecords);
                }
                
                serializedRecords.add(recordMap);
            }
            
            // Prepare final result
            result.put('objectType', objectType);
            result.put('recordCount', records.size());
            result.put('exportTimestamp', System.now());
            result.put('records', serializedRecords);
            result.put('objectMetadata', getObjectMetadata(objectDescribe));
            
        } catch (Exception e) {
            System.debug('Error getting object data for ' + objectType + ': ' + e.getMessage());
            result.put('error', e.getMessage());
            result.put('recordCount', 0);
            result.put('records', new List<Object>());
        }
        
        return result;
    }
    
    private Map<String, List<Map<String, Object>>> getRelatedRecords(Id recordId, Schema.DescribeSObjectResult objectDescribe) {
        Map<String, List<Map<String, Object>>> relatedRecords = new Map<String, List<Map<String, Object>>>();
        
        try {
            // Get child relationships
            List<Schema.ChildRelationship> childRelationships = objectDescribe.getChildRelationships();
            
            for (Schema.ChildRelationship childRel : childRelationships) {
                if (childRel.getRelationshipName() != null && 
                    childRel.getChildSObject().getDescribe().isAccessible()) {
                    
                    String childObjectType = String.valueOf(childRel.getChildSObject());
                    String relationshipField = String.valueOf(childRel.getField());
                    
                    // Limit related records to prevent performance issues
                    String relatedQuery = 'SELECT Id, Name FROM ' + childObjectType + 
                                        ' WHERE ' + relationshipField + ' = :recordId LIMIT 10';
                    
                    try {
                        List<SObject> relatedSObjects = Database.query(relatedQuery);
                        if (!relatedSObjects.isEmpty()) {
                            List<Map<String, Object>> relatedList = new List<Map<String, Object>>();
                            
                            for (SObject relatedRecord : relatedSObjects) {
                                Map<String, Object> relatedMap = new Map<String, Object>();
                                relatedMap.put('Id', relatedRecord.Id);
                                if (relatedRecord.get('Name') != null) {
                                    relatedMap.put('Name', relatedRecord.get('Name'));
                                }
                                relatedList.add(relatedMap);
                            }
                            
                            relatedRecords.put(childRel.getRelationshipName(), relatedList);
                        }
                    } catch (Exception relEx) {
                        System.debug('Error querying related records for ' + childObjectType + ': ' + relEx.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting related records: ' + e.getMessage());
        }
        
        return relatedRecords;
    }
    
    private Map<String, Object> getObjectMetadata(Schema.DescribeSObjectResult objectDescribe) {
        Map<String, Object> metadata = new Map<String, Object>();
        
        metadata.put('label', objectDescribe.getLabel());
        metadata.put('labelPlural', objectDescribe.getLabelPlural());
        metadata.put('keyPrefix', objectDescribe.getKeyPrefix());
        metadata.put('isCustom', objectDescribe.isCustom());
        metadata.put('isAccessible', objectDescribe.isAccessible());
        metadata.put('isCreateable', objectDescribe.isCreateable());
        metadata.put('isUpdateable', objectDescribe.isUpdateable());
        metadata.put('isDeletable', objectDescribe.isDeletable());
        
        return metadata;
    }
    
    private void logSuccess(String objectType, String s3Path, String etag, String fileName) {
        // You can create a custom object to log export results
        System.debug('SUCCESS - Exported ' + objectType + ' to ' + s3Path + ' with ETag: ' + etag);
        
        // Example of creating a log record (create custom object S3_Export_Log__c)
        /*
        S3_Export_Log__c log = new S3_Export_Log__c(
            Object_Type__c = objectType,
            S3_Path__c = s3Path,
            File_Name__c = fileName,
            Status__c = 'Success',
            ETag__c = etag,
            Export_Timestamp__c = System.now()
        );
        insert log;
        */
    }
    
    private void logError(String objectType, Exception e) {
        System.debug('ERROR - Failed to export ' + objectType + ': ' + e.getMessage());
        
        // Example of creating an error log record
        /*
        S3_Export_Log__c log = new S3_Export_Log__c(
            Object_Type__c = objectType,
            Status__c = 'Error',
            Error_Message__c = e.getMessage(),
            Export_Timestamp__c = System.now()
        );
        insert log;
        */
    }
    
    private void createExportSummary() {
        try {
            String fileName = 'export_summary_' + System.now().getTime() + '.json';
            String s3Path = 'salesforce-exports/summaries/' + fileName;
            
            exportMetadata.put('exportEndTime', System.now());
            exportMetadata.put('objectTypes', objectTypes);
            
            Map<String, Object> summaryData = new Map<String, Object>{
                'exportSummary' => exportMetadata,
                'processedObjects' => objectTypes,
                'generatedAt' => System.now()
            };
            
            Map<String, String> metadata = new Map<String, String>{
                'contentType' => 'summary',
                'exportTime' => String.valueOf(System.now()),
                'totalObjects' => String.valueOf(objectTypes.size())
            };
            
            Map<String, Object> payload = new Map<String, Object>{
                's3Bucket' => s3BucketName,
                's3Key' => s3Path,
                'content' => JSON.serialize(summaryData),
                'metadata' => metadata
            };
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(lambdaEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('Export summary created: ' + (res.getStatusCode() == 200 ? 'Success' : 'Failed'));
            
        } catch (Exception e) {
            System.debug('Error creating export summary: ' + e.getMessage());
        }
    }
}