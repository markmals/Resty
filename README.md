# Resty

Resty is a networking μframework built on Apple's [`Combine`](https://developer.apple.com/documentation/combine) asynchronous streams framework. It provides a simple, composable, protocol-oriented way to structure wrappers around simple REST APIs.

## Wrapping an API

To wrap an API, conform to the `API` protocol, add the `baseURL` for your service, and write `Publisher` returning functions. Conforming to the `API` protocol gives you access to the five HTTP verb methods (`get(path:)`, `post(path:)`, `put(path:)`, `patch(path:)`, `delete(path:)`), to which you can declaratively add request options and use all the other functional declarative operators that come with [`Publisher`](https://developer.apple.com/documentation/combine/publisher).

```swift
import Resty

struct Mailchimp: API {
    let baseURL = URL(string: "https://us7.api.mailchimp.com/3.0/")!
    var apiKey = env.mailchimpApiKey
    var authHeader: [String: String] { 
        ["Authorization": "Basic " + "anystring:\(apiKey)".base64Encoded] 
    }

    func addContent(for episode: Episode, toCampaign campaignID: String) -> AnyPublisher<Void, Error> {
        struct Edit: Encodable {
            var plain_text: String
            var html: String
        }

        let body = Edit(plain_text: plainText(episode), html: html(episode))
        
        return put(path: "campaigns/\(campaignID)/content")
            .body(body, encoder: JSONEncoder())
            .authorization(authHeader)
            .eraseToAnyPublisher()
    }
}
```

From here, you'll write a method for each endpoint you need from the API and they will each return an [`AnyPublisher<Output, Failure>`](https://developer.apple.com/documentation/combine/anypublisher), with the `Output` being the type of the response you recieve, or `Void`, if no response. From there you can use your API's `Publishers` in your app, binding them to UI controls in `viewDidLoad()` for UIKit or [assigning](https://developer.apple.com/documentation/combine/publisher/assign(to:)) them to [`@Published`](https://developer.apple.com/documentation/combine/published) properties on your SwiftUI ViewModel.
