Functions
===

Cloud Firebase Functions that power the various aspects of the app. To deploy,

```
$ npm run deploy --only functions
```

### Email

For sending emails via your firebase functions, you'd need to set your api_key for the service you're using. In this case, we use [Sendgrid](https://sendgrid.com).


```
$ firebase functions:config:set sendgrid.key="<API_KEY>"
```

### videoToImages

For this, add a service account key with name `service_account_key.json` in the `lib` folder as described [here](https://github.com/firebase/functions-samples/tree/master/generate-thumbnail#deploy-and-test).
