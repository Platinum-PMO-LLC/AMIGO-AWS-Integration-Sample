public class S3CalloutService { 
    // private static S3_Connection_Config__mdt getConfig() { 
    //     String env = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox ? 'Sandbox' : 'Production'; 
    //     return S3_Connection_Config__mdt.getInstance(env); 
    // } 
    public static void uploadFile(String fileName, String content, String contentType) { 
        // S3_Connection_Config__mdt config = getConfig(); 
        // if(config == null) { 
        //     throw new S3Exception('S3 configuration not found'); 
        // } 
        try { 
            // Prepare request 
            HttpRequest request = new HttpRequest(); 
            request.setMethod('PUT'); 
            request.setEndpoint('callout:AWS_S3/'+'salesforce-exports/'+ fileName); 
            request.setBody(content); 
            request.setHeader('Content-Type', contentType); 
            request.setTimeout(Integer.valueOf(60000)); 
            Http http = new Http(); 
            HttpResponse response = http.send(request); 
            if(response.getStatusCode() != 200) { 
                System.debug('S3 upload failed: ' + response.getStatusCode() + ' - ' + response.getBody()); 
            } 
            System.debug('Successfully uploaded file: ' + fileName); 
        } catch(Exception e) { 
            System.debug('Error uploading file to S3: ' + e.getMessage());
        } 
    } 

} 

 