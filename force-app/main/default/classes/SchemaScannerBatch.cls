public with sharing class SchemaScannerBatch implements Database.Batchable<String>, Database.Stateful {

    private List<Map<String, Object>> batchObjectMetadata = new List<Map<String, Object>>();

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
        exportSchemaAsync(schemaJSON);
        System.debug('Schema metadata saved successfully.' + schemaJSON);
    }
    // @future(callout=true)
    public static void exportSchemaAsync(String schemaJSON) {
        try {
            S3ExportUtility.exportSchemaToS3(schemaJSON);
        } catch (Exception e) {
            System.debug('Error in async export: ' + e.getMessage());
        }
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
}