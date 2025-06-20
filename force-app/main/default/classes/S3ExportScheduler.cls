global class S3ExportScheduler implements Schedulable {
    
    private Integer batchSize;
    
    global S3ExportScheduler() {
        this.batchSize = 5; 
    }
    
    global S3ExportScheduler(Integer batchSize) {
        this.batchSize = batchSize;
    }
    
    global void execute(SchedulableContext ctx) {
        try {
            // Get next batch of objects to process
            List<S3_Export_Queue__c> queueItems = S3ExportQueueManager.getNextBatch(batchSize);
            
            if(queueItems.isEmpty()) {
                System.debug('No items in export queue');
                return;
            }
            
            // Start batch jobs for each object
            for(S3_Export_Queue__c queueItem : queueItems) {
                // Update status to processing
                S3ExportQueueManager.updateQueueStatus(queueItem.Id, 'Processing', null);
                
                // Get chunk size from config
                S3_Export_Config__mdt config = S3_Export_Config__mdt.getInstance(queueItem.Object_Name__c);
                Integer chunkSize = (config != null) ? Integer.valueOf(config.Chunk_Size__c) : 5000;
                
                // Start batch job
                S3ExportBatch batchJob = new S3ExportBatch(
                    queueItem.Id, 
                    queueItem.Object_Name__c, 
                    chunkSize
                );
                
                Database.executeBatch(batchJob, Integer.valueOf(queueItem.Batch_Size__c));
            }
            
            // Schedule next run if more items exist
            scheduleNext();
            
        } catch(Exception e) {
            System.debug('Scheduler error: ' + e.getMessage());
            // Send error notification
            // S3ExportNotificationService.sendErrorNotification('Scheduler Error', e.getMessage());
        }
    }
    
    private void scheduleNext() {
        Integer remainingCount = [
            SELECT COUNT() 
            FROM S3_Export_Queue__c 
            WHERE Status__c IN ('Queued', 'Failed')
        ];
        
        if(remainingCount > 0) {
            // Schedule next run in 30 minutes
            String jobName = 'S3Export_' + System.now().getTime();
            String cronExp = S3ExportQueueManager.getCronExpression(1);
            
            System.schedule(jobName, cronExp, new S3ExportScheduler(batchSize));
        }
    }

}
