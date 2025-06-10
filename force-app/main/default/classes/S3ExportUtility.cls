public class S3ExportUtility {
    
    // Configuration - you can move these to Custom Settings or Custom Metadata
    private static final String DEFAULT_LAMBDA_ENDPOINT = 'https://9dvpq2fd45.execute-api.ap-south-1.amazonaws.com/default/UploadSFDataToS3';
    private static final String DEFAULT_S3_BUCKET = 'amigo-v-27-knowledge-base';
    
    public static void exportAllCustomObjects() {
        List<String> customObjects = getAllCustomObjects();
        exportObjectsToS3(customObjects);
    }
    
    public static void exportObjectsToS3(List<String> objectTypes) {
        exportObjectsToS3(objectTypes, DEFAULT_LAMBDA_ENDPOINT, DEFAULT_S3_BUCKET);
    }
    
    /**
     * Export specific objects to S3 with custom configuration
     */
    public static void exportObjectsToS3(List<String> objectTypes, String lambdaEndpoint, String s3BucketName) {
        if (objectTypes == null || objectTypes.isEmpty()) {
            System.debug('No object types provided for export');
            return;
        }
        
        System.debug('Starting S3 export for ' + objectTypes.size() + ' object types');
        
        // Start the queueable chain
        S3CustomObjectExportQueueable exportJob = new S3CustomObjectExportQueueable(
            objectTypes, 
            lambdaEndpoint, 
            s3BucketName
        );
        
        System.enqueueJob(exportJob);
        System.debug('S3 export job enqueued successfully');
    }
    @future(callout=true)
    public static void exportSchemaToS3(String schemaJSON) {
        try {
            // Generate filename with timestamp
            String fileName = 'Schema_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.json';
            String s3Path = 'salesforce-exports/Schema Object/' + fileName;
            
            // Prepare metadata
            Map<String, String> metadata = new Map<String, String>{
                'exportTime' => String.valueOf(System.now()),
                'salesforceOrg' => UserInfo.getOrganizationId(),
                'exportedBy' => UserInfo.getUserId()
            };
            
            // Prepare request payload for Lambda
            Map<String, Object> payload = new Map<String, Object>{
                's3Bucket' => DEFAULT_S3_BUCKET,
                's3Key' => s3Path,
                'content' => schemaJSON,
                'metadata' => metadata
            };
            
            // Send to Lambda
            HttpRequest req = new HttpRequest();
            req.setEndpoint(DEFAULT_LAMBDA_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                System.debug('Successfully exported schema to S3: ' + s3Path);
                Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                System.debug('SUCCESS - Exported schema with ETag: ' + responseData.get('etag'));
            } else {
                System.debug('Failed to export schema. Status: ' + res.getStatusCode() + ', Body: ' + res.getBody());
                throw new CalloutException('Lambda returned status: ' + res.getStatusCode());
            }
            
        } catch (Exception e) {
            System.debug('Error exporting schema: ' + e.getMessage());
            throw e;
        }
    }
    
    /**
     * Get all custom objects in the org
     */
    public static List<String> getAllCustomObjects() {
        List<String> customObjects = new List<String>();
        
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        for (String objectName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult objectDescribe = globalDescribe.get(objectName).getDescribe();
            
            // Include only custom objects that are accessible
            if (objectDescribe.isCustom() && 
                objectDescribe.isAccessible() && 
                objectDescribe.isQueryable() &&
                !objectName.endsWith('__History') &&
                !objectName.endsWith('__Share') &&
                !objectName.endsWith('__Feed') &&
                !objectName.endsWith('__Tag')) {
                customObjects.add(objectName);
            }
        }
        
        System.debug('Found ' + customObjects.size() + ' custom objects');
        return customObjects;
    }
    
    public static void exportAllObjects() {
        List<String> allObjects = new List<String>();
        // allObjects.addAll(getStandardObjects());
        allObjects.addAll(getAllCustomObjects());
        
        exportObjectsToS3(allObjects);
    }
    
    /**
     * Export with custom settings from Custom Metadata or Custom Settings
     */
    public static void exportWithCustomSettings(List<String> objectTypes) {
        // Example of using Custom Settings (create S3_Export_Settings__c custom setting)
        /*
        S3_Export_Settings__c settings = S3_Export_Settings__c.getInstance();
        String lambdaEndpoint = settings != null ? settings.Lambda_Endpoint__c : DEFAULT_LAMBDA_ENDPOINT;
        String s3Bucket = settings != null ? settings.S3_Bucket_Name__c : DEFAULT_S3_BUCKET;
        
        exportObjectsToS3(objectTypes, lambdaEndpoint, s3Bucket);
        */
        
        // For now, use defaults
        exportObjectsToS3(objectTypes);
    }
    
    /**
     * Schedule regular exports (use with Schedulable)
     */
    public static void scheduleRegularExport() {
        // This method can be called from a Schedulable class
        exportAllCustomObjects();
    }
}