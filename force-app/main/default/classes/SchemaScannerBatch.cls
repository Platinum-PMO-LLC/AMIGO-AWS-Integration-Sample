public with sharing class SchemaScannerBatch implements Database.Batchable<String>, Database.Stateful {

    private List<Map<String, Object>> batchObjectMetadata = new List<Map<String, Object>>();
    private static final String DEFAULT_LAMBDA_ENDPOINT = 'https://9dvpq2fd45.execute-api.ap-south-1.amazonaws.com/default/UploadSFDataToS3';
    private static final String DEFAULT_S3_BUCKET = 'amigo-v-27-knowledge-base';
    
    public Iterable<String> start(Database.BatchableContext bc) {
        // Collect custom object API names
        List<String> customObjects = new List<String>();
        for (String objectName : Schema.getGlobalDescribe().keySet()) {
            if (objectName.endsWith('__c')) {
                customObjects.add(objectName);
            }
        }
        return customObjects;
    }

    public void execute(Database.BatchableContext bc, List<String> customObjectNames) {
        for (String objectName : customObjectNames) {
            Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectName).getDescribe();
            Map<String, Object> objectMetadata = SchemaScanner.getObjectMetadata(objDescribe);
            batchObjectMetadata.add(new Map<String, Object>{
                objectName => objectMetadata
            });
        }
    }

    public void finish(Database.BatchableContext bc) {
        Map<String, Object> schema = new Map<String, Object>{
            'metadata' => SchemaScanner.getMetadata(),
            'objects' => mergeAllObjects(batchObjectMetadata),
            'relationship_rules' => SchemaScanner.getRelationshipRules()
        };

        String schemaJSON = JSON.serialize(schema);
        System.debug('Schema metadata saved successfully.' + schemaJSON);
        System.enqueueJob(new S3ExportQueueable(schemaJSON));
    }

    private Map<String, Object> mergeAllObjects(List<Map<String, Object>> metadataList) {
        Map<String, Object> merged = new Map<String, Object>();
        for (Map<String, Object> entry : metadataList) {
            for (String key : entry.keySet()) {
                merged.put(key, entry.get(key));
            }
        }
        return merged;
    }

    public class S3ExportQueueable implements Queueable, Database.AllowsCallouts {
        private String schemaJSON;
        
        public S3ExportQueueable(String schemaJSON) {
            this.schemaJSON = schemaJSON;
        }

        public void execute(QueueableContext context) {
            S3ExportUtility.exportSchemaToS3(this.schemaJSON);
        }

        // private void exportSchemaToS3(String schemaJSON) {
        //     try {
        //         // Generate filename with timestamp
        //         String fileName = 'Schema_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.json';
        //         String s3Path = 'salesforce-exports/Schema-Object/' + fileName;
                
        //         // Prepare metadata
        //         Map<String, String> metadata = new Map<String, String>{
        //             'exportTime' => String.valueOf(System.now()),
        //             'salesforceOrg' => UserInfo.getOrganizationId(),
        //             'exportedBy' => UserInfo.getUserId()
        //         };
                
        //         // Prepare request payload for Lambda
        //         Map<String, Object> payload = new Map<String, Object>{
        //             's3Bucket' => DEFAULT_S3_BUCKET,
        //             's3Key' => s3Path,
        //             'content' => schemaJSON,
        //             'metadata' => metadata
        //         };
                
        //         // Send to Lambda
        //         HttpRequest req = new HttpRequest();
        //         req.setEndpoint(DEFAULT_LAMBDA_ENDPOINT);
        //         req.setMethod('POST');
        //         req.setHeader('Content-Type', 'application/json');
        //         req.setBody(JSON.serialize(payload));
        //         req.setTimeout(120000);
                
        //         Http http = new Http();
        //         HttpResponse res = http.send(req);
                
        //         if (res.getStatusCode() == 200) {
        //             System.debug('Successfully exported schema to S3: ' + s3Path);
        //             Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        //             System.debug('SUCCESS - Exported schema with ETag: ' + responseData.get('etag'));
        //         } else {
        //             System.debug('Failed to export schema. Status: ' + res.getStatusCode() + ', Body: ' + res.getBody());
        //             throw new CalloutException('Lambda returned status: ' + res.getStatusCode());
        //         }
                
        //     } catch (Exception e) {
        //         System.debug('Error exporting schema: ' + e.getMessage());
        //         System.debug('Stack trace: ' + e.getStackTraceString());
        //     }
        // }
    }
}