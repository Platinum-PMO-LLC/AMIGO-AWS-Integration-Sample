/**
 * Test class for AWSLambdaCallout
 */
@isTest
private class AWSLambdaCalloutTest {
    /**
     * Test the Lambda callout with a mock response
     */
    @isTest
    static void testLambdaCallout() {
        // Create the mock callout response
        Test.setMock(HttpCalloutMock.class, new AWSLambdaMock());
        
        // Call the method to test
        Test.startTest();
        HttpResponse response = AWSLambdaCallout.callSumNumbersLambda(15, 20);
        Integer result = AWSLambdaCallout.getSumResult(15, 20);
        String message = AWSLambdaCallout.getResponseMessage(15, 20);
        Test.stopTest();
        
        // Verify the response
        System.debug(response.getBody());
        System.assertEquals(200, response.getStatusCode());
        System.assertEquals('{"num1":15,"num2":20,"sum":35,"message":"The sum of 15 and 20 is 35"}', response.getBody());
        System.assertEquals(35, result);
        System.assertEquals('The sum of 15 and 20 is 35', message);
    }
    
    /**
     * Mock class for AWS Lambda HTTP callout
     */
    private class AWSLambdaMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            // Verify request properties
            System.assertEquals('https://wczahn50ec.execute-api.ap-south-1.amazonaws.com/default/SumNumbersAbhasita', request.getEndpoint());
            System.assertEquals('POST', request.getMethod());
            
            // Parse the request body to get the input parameters
            Map<String, Object> requestBody = (Map<String, Object>)JSON.deserializeUntyped(request.getBody());
            Integer num1 = Integer.valueOf(requestBody.get('num1'));
            Integer num2 = Integer.valueOf(requestBody.get('num2'));
            Integer sum = num1 + num2;
            
            // Create a mock response matching the actual response format
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"num1":' + num1 + ',"num2":' + num2 + ',"sum":' + sum + ',"message":"The sum of ' + num1 + ' and ' + num2 + ' is ' + sum + '"}');
            return response;
        }
    }
} 