# Resty

Resty is a networking μframework built on Apple's [`Combine`](https://developer.apple.com/documentation/combine) asynchronous streams framework. It provides a simple, composable, protocol-oriented way to structure wrappers around simple REST APIs.

## Wrapping an API

To wrap an API, conform to the `API` protocol, add the `baseURL` for your service, and write `Publisher` returning functions. Conforming to the `API` protocol gives you access to the five HTTP verb methods (`get(path:)`, `post(path:)`, `put(path:)`, `patch(path:)`, `delete(path:)`), to which you can declaratively add request options and get a publisher from, on which you can use all the functional declarative operators that come with [`Publisher`](https://developer.apple.com/documentation/combine/publisher).

```swift
import Resty

struct SwiftForums: API {
    let baseURL = URL(string: "https://forums.swift.org")!
    lazy var decoder: JSONDecoder = {
        var decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    
    func search(term: String, includeBlurbs blurbs: Bool = false) -> AnyPublisher<SearchResult, Error> {
        get(path: "/search")
            .queryItems(["q": term, "include_blurbs": "\(blurbs)"])
            .publisher()
    }
    
    func latestPosts() -> AnyPublisher<[LatestPost], Error> {
        struct LatestPosts: Decodable {
            let latestPosts: [LatestPost]
        }
        
        return get(path: "/posts.json")
            .publisher()
            .decode(type: LatestPosts.self, decoder: decoder)
            .map(\.latestPosts)
            .eraseToAnyPublisher()
    }
}
```

From here, you'll write a method for each endpoint you need from the API and they will each return an [`AnyPublisher<Output, Failure>`](https://developer.apple.com/documentation/combine/anypublisher), with the `Output` being the type of the response you recieve, or `Void`, if no response. From there you can use your API's `Publishers` in your app, binding them to UI controls in `viewDidLoad()` for UIKit or [assigning](https://developer.apple.com/documentation/combine/publisher/assign(to:)) them to [`@Published`](https://developer.apple.com/documentation/combine/published) properties on your SwiftUI ViewModel.
