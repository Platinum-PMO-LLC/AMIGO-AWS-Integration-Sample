/**
 * Class to demonstrate making actual callouts to AWS Lambda endpoint
 * This is for demonstration purposes - not meant for test methods
 */
public with sharing class AWSLambdaActualCallout {
    /**
     * Makes a real callout to the AWS Lambda function with the specified numbers
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return The sum result from the Lambda function
     */
    @AuraEnabled
    public static Integer makeRealCallout(Integer num1, Integer num2) {
        try {
            // Use the AWSLambdaCallout class to make the actual callout
            HttpResponse response = AWSLambdaCallout.callSumNumbersLambda(num1, num2);
            
            if (response.getStatusCode() == 200) {
                // Parse response
                Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                
                // Use sum field from actual response format
                if (resultMap.containsKey('sum')) {
                    return Integer.valueOf(resultMap.get('sum'));
                }
                // Fallback to result for backward compatibility
                else if (resultMap.containsKey('result')) {
                    return Integer.valueOf(resultMap.get('result'));
                }
                
                System.debug('Response did not contain sum or result key: ' + response.getBody());
                return null;
            } else {
                System.debug('Error response: ' + response.getStatusCode() + ' ' + response.getStatus());
                System.debug('Response body: ' + response.getBody());
                return null;
            }
        } catch (Exception e) {
            System.debug('Exception during real callout: ' + e.getMessage());
            throw e;
        }
    }
    
    /**
     * Makes a real callout using the default values from the requirements
     * @return The sum result
     */
    @AuraEnabled
    public static Integer makeDefaultCallout() {
        return makeRealCallout(15, 20);
    }
    
    /**
     * Makes a real callout and returns full response information
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return String with status code and response body
     */
    @AuraEnabled
    public static String getFullResponse(Integer num1, Integer num2) {
        try {
            HttpResponse response = AWSLambdaCallout.callSumNumbersLambda(num1, num2);
            return 'Status: ' + response.getStatusCode() + '\nBody: ' + response.getBody();
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    /**
     * Get the message from the Lambda response
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return The message from the response
     */
    @AuraEnabled
    public static String getResponseMessage(Integer num1, Integer num2) {
        try {
            return AWSLambdaCallout.getResponseMessage(num1, num2);
        } catch (Exception e) {
            System.debug('Error getting response message: ' + e.getMessage());
            return 'Error: ' + e.getMessage();
        }
    }
} 