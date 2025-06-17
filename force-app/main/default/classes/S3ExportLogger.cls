public with sharing class S3ExportLogger {
    
    public static void logBatchStart(Id queueId, Id jobId, String objectName) {
        S3_Export_Log__c log = new S3_Export_Log__c(
            S3_Export_Queue__c = queueId,
            Batch_Job_Id__c = jobId,
            Status__c = 'Started',
            Processing_Time__c = System.now().getTime()
        );
        insert log;
    }
    
    public static void logBatchSuccess(Id queueId, Id jobId, Integer recordCount, String fileName) {

        List<S3_Export_Log__c> existingLogs = [
            SELECT Id, Records_Processed__c, File_Name__c, S3_Export_Queue__c
            FROM S3_Export_Log__c
            WHERE S3_Export_Queue__c = :queueId
            LIMIT 1
        ];

        if (!existingLogs.isEmpty()) {
            S3_Export_Log__c log = existingLogs[0];
            log.Status__c = 'Completed';
            log.Records_Processed__c = recordCount;
            log.File_Name__c = fileName;
            update log;
        } else {
            S3_Export_Log__c log = new S3_Export_Log__c(
                S3_Export_Queue__c = queueId,
                Batch_Job_Id__c = jobId,
                Status__c = 'Completed',
                Records_Processed__c = recordCount,
                File_Name__c = fileName
            );
            insert log;
        }
    }
    
    public static void logBatchError(Id queueId, Id jobId, String errorMessage) {

        List<S3_Export_Log__c> existingLogs = [
            SELECT Id, Records_Processed__c, File_Name__c, S3_Export_Queue__c
            FROM S3_Export_Log__c
            WHERE S3_Export_Queue__c = :queueId
            LIMIT 1
        ];

        if (!existingLogs.isEmpty()) {
            S3_Export_Log__c log = existingLogs[0];
            log.Status__c = 'Failed';
            log.Error_Details__c = errorMessage;
            update log;
        } else {
            S3_Export_Log__c log = new S3_Export_Log__c(
                S3_Export_Queue__c = queueId,
                Batch_Job_Id__c = jobId,
                Status__c = 'Failed',
                Error_Details__c = errorMessage
            );
            insert log;
        }
    }
    
    public static void logBatchFinish(Id queueId, Id jobId, String status, Integer recordsProcessed, Integer filesCreated) {
        // Update or create final log entry
        List<S3_Export_Log__c> existingLogs = [
            SELECT Id FROM S3_Export_Log__c 
            WHERE S3_Export_Queue__c = :queueId AND Batch_Job_Id__c = :jobId 
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        
        if(!existingLogs.isEmpty()) {
            S3_Export_Log__c log = new S3_Export_Log__c(
                Id = existingLogs[0].Id,
                Status__c = status,
                Records_Processed__c = recordsProcessed,
                Files_Created__c = filesCreated
                // Processing_Time__c = System.now().getTime() - log.Processing_Time__c
            );
            update log;
        }
    }
}