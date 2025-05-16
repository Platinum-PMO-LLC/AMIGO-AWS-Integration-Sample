/**
 * Example class demonstrating AWSLambdaCallout usage
 */
public with sharing class AWSLambdaExample {
    /**
     * Example method demonstrating how to invoke the AWS Lambda function
     * with the default values from the requirements (15 and 20)
     * @return The result from the Lambda function
     */
    public static Integer invokeDefaultExample() {
        try {
            // Using the default values from the requirements: num1=15, num2=20
            Integer result = AWSLambdaCallout.getSumResult(15, 20);
            System.debug('Sum result from AWS Lambda: ' + result);
            return result;
        } catch (Exception e) {
            System.debug('Error in invokeDefaultExample: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Example method demonstrating how to invoke the AWS Lambda function
     * with custom values
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return The result from the Lambda function
     */
    public static Integer invokeCustomExample(Integer num1, Integer num2) {
        try {
            Integer result = AWSLambdaCallout.getSumResult(num1, num2);
            System.debug('Sum result from AWS Lambda: ' + result);
            return result;
        } catch (Exception e) {
            System.debug('Error in invokeCustomExample: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Example method demonstrating how to get the raw HTTP response
     * @param num1 First number to sum
     * @param num2 Second number to sum
     * @return The HTTP response as a string
     */
    public static String getRawResponse(Integer num1, Integer num2) {
        try {
            HttpResponse response = AWSLambdaCallout.callSumNumbersLambda(num1, num2);
            return 'Status: ' + response.getStatusCode() + ', Body: ' + response.getBody();
        } catch (Exception e) {
            System.debug('Error in getRawResponse: ' + e.getMessage());
            return 'Error: ' + e.getMessage();
        }
    }
} 