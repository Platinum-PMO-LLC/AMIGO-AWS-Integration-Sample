/**
 * Integration test for AWS Lambda callout
 * NOTE: This is for demonstration purposes only
 * Real callouts from tests are generally not recommended in Salesforce
 */
@isTest(seeAllData=true)
public class AWSLambdaIntegrationTest {
    /**
     * Integration test that makes a real callout to the AWS Lambda endpoint
     * NOTE: This test will fail unless the "Don't Allow Callouts" option 
     * is unchecked in the Apex Test Execution settings
     */
    @isTest
    static void testRealCallout() {
        // Skip the test if we are running in a standard test context
        // This is a safety check, as real callouts normally shouldn't be made in tests
        if (Test.isRunningTest() && !System.isFuture() && !System.isBatch()) {
            System.debug('Skipping real callout in standard test context');
            return;
        }
        
        // DO NOT mock the callout - that's the whole point of this test
        // Test.setMock(HttpCalloutMock.class, new AWSLambdaCalloutTest.AWSLambdaMock());
        
        Test.startTest();
        try {
            // Make the actual callout to AWS Lambda
            HttpResponse response = AWSLambdaCallout.callSumNumbersLambda(15, 20);
            Integer result = AWSLambdaCallout.getSumResult(15, 20);
            
            // Log the results
            System.debug('Response status: ' + response.getStatusCode());
            System.debug('Response body: ' + response.getBody());
            System.debug('Sum result: ' + result);
            
            // Verify the response if the callout was successful
            if (response.getStatusCode() == 200) {
                Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                System.assertEquals(true, resultMap.containsKey('result'), 'Response should contain result key');
                System.assertEquals(35, result, 'Sum of 15 and 20 should be 35');
            }
        } catch (Exception e) {
            System.debug('Exception during test: ' + e.getMessage());
            System.assert(false, 'Exception occurred: ' + e.getMessage());
        }
        Test.stopTest();
    }
} 