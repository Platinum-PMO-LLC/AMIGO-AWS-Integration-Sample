public with sharing class SchemaScanner {
   
    // Main method to generate complete schema JSON
    // @AuraEnabled
    // public static String generateFullSchemaJSON() {
    //     Map<String, Object> schema = new Map<String, Object>{
    //         'metadata' => getMetadata(),
    //         'objects' => getAllObjectsMetadata(),
    //         'relationship_rules' => getRelationshipRules()
    //     };
        
    //     // Serialize without escape characters
    //     String schemaJSON = JSON.serialize(schema);
    //     System.debug(schemaJSON);
    //     return JSON.serialize(schema);
    // }
    
    // Get metadata about the schema itself
    public static Map<String, Object> getMetadata() {
        return new Map<String, Object>{
            'schema_name' => 'Salesforce_Dynamic_Schema',
            'version' => '1.0',
            'description' => 'Auto-generated schema of all custom objects',
            'generated_date' => Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
            'api_version' => [SELECT ApiVersion FROM ApexClass LIMIT 1].ApiVersion
        };
    }
    
    // Get all custom objects with their full metadata
   private static Map<String, Object> getAllObjectsMetadata() {
        Map<String, Object> objectsMap = new Map<String, Object>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        Integer count = 0;
        for (String objectName : globalDescribe.keySet()) {
            // Only process custom objects
            if (objectName.endsWith('__c')) {
                Schema.DescribeSObjectResult objDescribe = globalDescribe.get(objectName).getDescribe();
                objectsMap.put(objectName, getObjectMetadata(objDescribe));
                count++;
                
                // Break the loop after processing 5 objects
                if (count >= 5) {
                    break;
                }
            }
        }
        
        return objectsMap;
    }

    
    // Get detailed metadata for a single object
    public static Map<String, Object> getObjectMetadata(Schema.DescribeSObjectResult objDescribe) {
        Map<String, Object> objectMeta = new Map<String, Object>{
            'id' => objDescribe.getName().toLowerCase().replace('__c', ''),
            'api_name' => objDescribe.getName(),
            'label' => objDescribe.getLabel(),
            'description' => objDescribe.getLabelPlural(),
            'is_custom' => objDescribe.isCustom(),
            'is_queryable' => objDescribe.isQueryable(),
            'is_deletable' => objDescribe.isDeletable(),
            'is_creatable' => objDescribe.isCreateable(),
            'is_updatable' => objDescribe.isUpdateable(),
            'key_prefix' => objDescribe.getKeyPrefix(),
            'fields' => getFieldsMetadata(objDescribe),
            'relationships' => getRelationshipsMetadata(objDescribe),
            'record_types' => getRecordTypesMetadata(objDescribe.getName())
        };
        
        return objectMeta;
    }
    
    // Get all fields for an object
    private static Map<String, Object> getFieldsMetadata(Schema.DescribeSObjectResult objDescribe) {
        Map<String, Object> fieldsMap = new Map<String, Object>();
        Map<String, Schema.SObjectField> fields = objDescribe.fields.getMap();
        
        for(String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
            fieldsMap.put(fieldName, getFieldMetadata(fieldDescribe));
        }
        
        return fieldsMap;
    }
    
    // Get metadata for a single field
    private static Map<String, Object> getFieldMetadata(Schema.DescribeFieldResult fieldDescribe) {
        Map<String, Object> fieldMeta = new Map<String, Object>{
            'name' => fieldDescribe.getName(),
            'label' => fieldDescribe.getLabel(),
            'type' => fieldDescribe.getType().name(),
            'length' => fieldDescribe.getLength(),
            'is_custom' => fieldDescribe.isCustom(),
            'is_required' => !fieldDescribe.isNillable(),
            'is_unique' => fieldDescribe.isUnique(),
            'default_value' => fieldDescribe.getDefaultValue(),
            'reference_to' => new List<String>()
        };
        
        if(fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
            for(Schema.SObjectType reference : fieldDescribe.getReferenceTo()) {
                ((List<String>)fieldMeta.get('reference_to')).add(reference.getDescribe().getName());
            }
        }
        
        if(fieldDescribe.getType() == Schema.DisplayType.PICKLIST) {
            fieldMeta.put('picklist_values', getPicklistValues(fieldDescribe));
        }
        
        return fieldMeta;
    }
    
    // Get picklist values for a field
    private static List<Map<String, String>> getPicklistValues(Schema.DescribeFieldResult fieldDescribe) {
        List<Map<String, String>> picklistValues = new List<Map<String, String>>();
        for(Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if(entry.isActive()) {
                picklistValues.add(new Map<String, String>{
                    'value' => entry.getValue(),
                    'label' => entry.getLabel(),
                    'default' => String.valueOf(entry.isDefaultValue())
                });
            }
        }
        return picklistValues;
    }
    
    // Get all relationships for an object
    private static Map<String, Object> getRelationshipsMetadata(Schema.DescribeSObjectResult objDescribe) {
        Map<String, Object> relationshipsMap = new Map<String, Object>{
            'child_relationships' => getChildRelationships(objDescribe),
            'lookup_fields' => getLookupFields(objDescribe)
        };
        return relationshipsMap;
    }
    
    // Get child relationships (where this object is the parent)
    private static List<Map<String, Object>> getChildRelationships(Schema.DescribeSObjectResult objDescribe) {
        List<Map<String, Object>> childRelationships = new List<Map<String, Object>>();
        
        for(Schema.ChildRelationship childRel : objDescribe.getChildRelationships()) {
            if(childRel.getRelationshipName() != null) {
                childRelationships.add(new Map<String, Object>{
                    'relationship_name' => childRel.getRelationshipName(),
                    'child_object' => childRel.getChildSObject().getDescribe().getName(),
                    'field_name' => childRel.getField().getDescribe().getName(),
                    'is_cascade_delete' => childRel.isCascadeDelete(),
                    'is_deprecated' => childRel.isDeprecatedAndHidden(),
                    'is_restricted_delete' => childRel.isRestrictedDelete()
                });
            }
        }
        
        return childRelationships;
    }
    
    // Get lookup fields (where this object is the child)
    private static List<Map<String, Object>> getLookupFields(Schema.DescribeSObjectResult objDescribe) {
        List<Map<String, Object>> lookupFields = new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fields = objDescribe.fields.getMap();
        
        for(String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
            if(fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<String> referenceTo = new List<String>();
                for(Schema.SObjectType reference : fieldDescribe.getReferenceTo()) {
                    referenceTo.add(reference.getDescribe().getName());
                }
                
                lookupFields.add(new Map<String, Object>{
                    'field_name' => fieldDescribe.getName(),
                    'relationship_name' => fieldDescribe.getRelationshipName(),
                    'reference_to' => referenceTo,
                    'is_cascade_delete' => fieldDescribe.isCascadeDelete(),
                    'is_restricted_delete' => fieldDescribe.isRestrictedDelete()
                });
            }
        }
        
        return lookupFields;
    }
    
    // Get record type information for an object
    private static List<Map<String, String>> getRecordTypesMetadata(String objectName) {
        List<Map<String, String>> recordTypes = new List<Map<String, String>>();
        
        try {
            for(RecordTypeInfo rtInfo : Schema.getGlobalDescribe().get(objectName).getDescribe().getRecordTypeInfos()) {
                if(rtInfo.isAvailable() && !rtInfo.isMaster()) {
                    recordTypes.add(new Map<String, String>{
                        'name' => rtInfo.getName(),
                        'developer_name' => rtInfo.getDeveloperName(),
                        'record_type_id' => rtInfo.getRecordTypeId()
                    });
                }
            }
        } catch(Exception e) {
            // Object may not have record types enabled
        }
        
        return recordTypes;
    }
    
    // Define standard relationship rules
    public static Map<String, Object> getRelationshipRules() {
        return new Map<String, Object>{
            'lookup' => new Map<String, Object>{
                'description' => 'Standard lookup relationship',
                'cardinality' => 'Many-to-One',
                'behavior' => 'Non-cascading delete'
            },
            'master_detail' => new Map<String, Object>{
                'description' => 'Strong relationship with ownership',
                'cardinality' => 'Many-to-One',
                'behavior' => 'Cascading delete'
            },
            'junction' => new Map<String, Object>{
                'description' => 'Many-to-Many via junction object',
                'cardinality' => 'Many-to-Many',
                'behavior' => 'Configurable delete'
            }
        };
    }
}