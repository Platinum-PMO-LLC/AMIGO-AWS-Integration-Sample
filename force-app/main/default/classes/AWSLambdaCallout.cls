/**
 * Class to handle AWS Lambda function callout
 */
public with sharing class AWSLambdaCallout {
    private static final String ENDPOINT = 'https://wczahn50ec.execute-api.ap-south-1.amazonaws.com/default/SumNumbersAbhasita';
    
    /**
     * Makes a callout to the AWS Lambda function to sum two numbers
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return The HTTP response from the AWS Lambda function
     */
    public static HttpResponse callSumNumbersLambda(Integer num1, Integer num2) {
        // Create HTTP request
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        
        // Create request body
        Map<String, Integer> requestBody = new Map<String, Integer>();
        requestBody.put('num1', num1);
        requestBody.put('num2', num2);
        
        // Set request body
        request.setBody(JSON.serialize(requestBody));
        
        // Send the request
        Http http = new Http();
        HttpResponse response;
        
        try {
            response = http.send(request);
            return response;
        } catch (Exception e) {
            System.debug('Error calling AWS Lambda: ' + e.getMessage());
            throw e;
        }
    }
    
    /**
     * Invokes the Lambda function and returns the sum result
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return The sum result
     */
    public static Integer getSumResult(Integer num1, Integer num2) {
        HttpResponse response = callSumNumbersLambda(num1, num2);
        
        if (response.getStatusCode() == 200) {
            // Parse the response body to get the result
            Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
            
            // Check for 'sum' field in the response (based on actual response format)
            if (resultMap.containsKey('sum')) {
                return Integer.valueOf(resultMap.get('sum'));
            }
            // Fallback to check for 'result' field for backward compatibility
            else if (resultMap.containsKey('result')) {
                return Integer.valueOf(resultMap.get('result'));
            }
            
            System.debug('Response does not contain sum or result field: ' + response.getBody());
            return null;
        } else {
            System.debug('Error response: ' + response.getStatusCode() + ' ' + response.getStatus());
            System.debug('Response body: ' + response.getBody());
            return null;
        }
    }
    
    /**
     * Get the message from the Lambda response
     * @param num1 First number
     * @param num2 Second number
     * @return The message from the response, or null if not present
     */
    public static String getResponseMessage(Integer num1, Integer num2) {
        HttpResponse response = callSumNumbersLambda(num1, num2);
        
        if (response.getStatusCode() == 200) {
            Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
            if (resultMap.containsKey('message')) {
                return (String)resultMap.get('message');
            }
            return null;
        } else {
            System.debug('Error response: ' + response.getStatusCode() + ' ' + response.getStatus());
            return null;
        }
    }
} 