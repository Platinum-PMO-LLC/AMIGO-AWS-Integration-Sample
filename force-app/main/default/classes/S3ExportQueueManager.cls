public with sharing class S3ExportQueueManager {

    public static void initializeExportQueue() {
        List<S3_Export_Config__mdt> configs = S3_Export_Config__mdt.getAll().values();
        List<S3_Export_Queue__c> queueItems = new List<S3_Export_Queue__c>();
        
        for(S3_Export_Config__mdt config : configs) {
            if(config.Is_Active__c) {
                queueItems.add(new S3_Export_Queue__c(
                    Object_Name__c = config.Object_Name__c,
                    Status__c = 'Queued',
                    Priority__c = config.Priority__c,
                    Batch_Size__c = config.Batch_Size__c,
                    File_Prefix__c = config.Object_Name__c
                ));
            }
        }
        
        if(!queueItems.isEmpty()) {
            insert queueItems;
            System.debug('Initialized ' + queueItems.size() + ' export queue items');
        }
    }

    public static List<S3_Export_Queue__c> getNextBatch(Integer batchSize) {
        return [
            SELECT Id, Object_Name__c, Batch_Size__c, File_Prefix__c, Priority__c
            FROM S3_Export_Queue__c 
            WHERE Status__c = 'Queued' 
            ORDER BY Priority__c ASC, CreatedDate ASC 
            LIMIT :batchSize
        ];
    }

    public static void updateQueueStatus(Id queueId, String status, String errorMessage) {
        S3_Export_Queue__c queueItem = new S3_Export_Queue__c(
            Id = queueId,
            Status__c = status
        );
        
        if(status == 'Processing') {
            queueItem.Started_Date__c = System.now();
        } else if(status == 'Completed') {
            queueItem.Completed_Date__c = System.now();
        } else if(status == 'Failed') {
            queueItem.Error_Message__c = errorMessage;
            queueItem.Retry_Count__c = (queueItem.Retry_Count__c ?? 0) + 1;
        }
        
        update queueItem;
    }

    public static String getCronExpression(Integer minutesFromNow) {
        DateTime nextRun = System.now().addMinutes(minutesFromNow);
        Integer seconds = nextRun.second();
        Integer minutes = nextRun.minute();
        Integer hours = nextRun.hour();
        Integer day = nextRun.day();
        Integer month = nextRun.month();
        Integer year = nextRun.year();
        
        return seconds + ' ' + minutes + ' ' + hours + ' ' + day + ' ' + month + ' ? ' + year;
    }

}