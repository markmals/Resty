//
//  File.swift
//  
//
//  Created by Mark Malstrom on 7/21/20.
//

import Foundation

struct Reddit: API {
    let base = URL(string: "https://api.reddit.com")!
    let auth = ["Authorization": "BEARER ****************"]
    
    func frontPage() -> AnyPublisher<[Post], Error> {
        GetPublisher("/front-page")
            .authorization(auth)
            .eraseToAnyPublisher()
    }
    
    func upload(post: SelfPost) -> AnyPublisher<(), Error> {
        PostPublisher("/new-selfpost")
            .authorization(auth)
            .body(post, encoder: JSONEncoder())
            .eraseToAnyPublisher()
    }
}
