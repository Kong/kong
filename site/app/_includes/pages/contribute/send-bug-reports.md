## Send Bug Reports

If you think you have found a bug in Kong, first make sure that you are testing against the [latest version of Kong](/download) &mdash; your issue may already have been fixed. If not, search our [issues list on GitHub]({{site.repo}}/issues) in case a similar issue has already been opened.

It is very helpful if you can prepare a reproduction of the bug. In other words, provide a small test case which we can run to confirm your bug. It makes it easier to find the problem and to fix it. Test cases should be provided as curl commands which we can copy and paste into a terminal to run it locally, for example:

```bash
# delete the API
curl -XDELETE 127.0.0.1:8001/apis/a2e8fccf-96b2-46c0-c6dd-4d0e968660b7

# insert a new API
curl -XPOST 127.0.0.1:8001/apis/
-d 'name=Mockbin' \
-d 'public_dns=api.mockbin.com' \
-d 'target_url=http://mockbin.com'

# this should return XXXX but instead returns YYY
curl ...
```

Provide as much information as you can. You may think that the problem lies with your query, when actually it depends on how your data is stored. The easier it is for us to recreate your problem, the faster it is likely to be fixed.

<a href="{{site.repo}}/issues/new" class="button button-primary button-large" target="_blank">Report a bug in Github</a>
