//
//  PostService.swift
//  InstaClone
//
//  Created by Giorgi on 1/4/21.
//

import Firebase
import UIKit

struct PostService {
    
    static func uploadPost(caption: String, image: UIImage, user: User,
                           completion: @escaping (FirestoreCompletion)) {
        
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let uuid = NSUUID().uuidString
        let directoryName = FireStoreDirectory.posts
        
        ImageService.uploadImage(image: image, uuid: uuid, directory: directoryName) { imageUrl in
            let data = [Resources.caption : caption,
                        Resources.timestamp : Timestamp(date: Date()),
                        Resources.likes : 0,
                        Resources.imageUrl : imageUrl,
                        Resources.ownerUid : uid,
                        Resources.imageUid : uuid] as [String : Any]
            
            let docRef = API.collectionPosts.addDocument(data: data, completion: completion)
            
            updateUserFeedAfterPost(postId: docRef.documentID)
        }
    }
    
    static func fetchPost(withPostId postId: String, completion: @escaping(Post) -> Void) {
        API.collectionPosts.document(postId).getDocument { snapshot, _ in
            guard let snapshot = snapshot,
                  let data = snapshot.data() else {return}
            
            let post = Post(postId: snapshot.documentID, dictionary: data)
            completion(post)
        }
    }
    
    static func fetchPosts(completion: @escaping([Post]) -> Void) {
        API.collectionPosts.order(by: Resources.timestamp, descending: true).getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else {return}
            
            let posts = documents.map { Post(postId: $0.documentID, dictionary: $0.data())}
            
            
            completion(posts)
        }
    }
    
    static func fetchPosts(forUser uid: String, completion: @escaping([Post]) -> Void) {
        let query = API.collectionPosts.whereField(Resources.ownerUid, isEqualTo: uid)
        
        query.getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else {return}
            
            var posts = documents.map { Post(postId: $0.documentID, dictionary: $0.data())}
            
            posts.sort { $0.timestamp.seconds > $1.timestamp.seconds}
            
            completion(posts)
        }
    }
    
   
    
    static func likePost(post: Post, completion: @escaping(FirestoreCompletion)) {
        guard let uid = Auth.auth().currentUser?.uid else {return}
        
        API.collectionPosts.document(post.postId).updateData([Resources.likes : post.likes + 1])
        
        API.collectionPosts.document(post.postId).collection(Resources.postLikes).document(uid).setData([:]) { _ in
            API.collectionUsers.document(uid).collection(Resources.userLikes).document(post.postId).setData([:], completion: completion)
        }
    }
    
    static func unlikePost(post: Post, completion: @escaping(FirestoreCompletion)) {
        guard let uid = Auth.auth().currentUser?.uid,
              post.likes > 0 else {return}
        
        API.collectionPosts.document(post.postId).updateData([Resources.likes : post.likes - 1])
        
        API.collectionPosts.document(post.postId).collection(Resources.postLikes).document(uid).delete { _ in
            API.collectionUsers.document(uid).collection(Resources.userLikes).document(post.postId).delete(completion: completion)
        }
    }
    
    static func checkIfUserLiked(post: Post, completion: @escaping(Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {return}

        API.collectionUsers.document(uid).collection(Resources.userLikes).document(post.postId).getDocument { snapshot, _ in
            
            guard let isLiked = snapshot?.exists else {return}
            completion(isLiked)
        }
    }
    
    static func updateUserFeedAfterFollowing(user: User, didFollow: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else {return}
        let query = API.collectionPosts.whereField(Resources.ownerUid, isEqualTo: user.uid)
        
        query.getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else {return}
            
            let docIds = documents.map {$0.documentID}
            
            docIds.forEach { id in
                
            if didFollow {
                API.collectionUsers.document(uid).collection(Resources.userFeed).document(id).setData([:])
            } else {
                API.collectionUsers.document(uid).collection(Resources.userFeed).document(id).delete()
                }
            }
        }
    }
    
    static func fetchFeedPosts(completion:@escaping([Post]) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {return}
        var posts = [Post]()

        API.collectionUsers.document(uid).collection(Resources.userFeed).getDocuments { snapshot, error in
            snapshot?.documents.forEach({ document in
                fetchPost(withPostId: document.documentID) { post in
                    posts.append(post)
                    completion(posts)
                }
            })
        }
    }
    
    
    private static func updateUserFeedAfterPost(postId: String) {
        guard let uid = Auth.auth().currentUser?.uid else {return}
        
        API.collectionFollowers.document(uid).collection(Resources.userFollowers).getDocuments { snapshot, _ in
            guard let documents = snapshot?.documents else {return}
            
            documents.forEach { document in
                API.collectionUsers.document(document.documentID).collection(Resources.userFeed).document(postId).setData([:])
            }
            
            API.collectionUsers.document(uid).collection(Resources.userFeed).document(postId).setData([:])
        }
    }
    
    static func checkIfPostBelongsToCurrentUser(post: Post, completion: @escaping(Bool) -> Void) {
            guard let uid = Auth.auth().currentUser?.uid else {return}
            var belongsTuUser = false
        
        fetchPosts(forUser: uid) { currentUserPosts in
            currentUserPosts.forEach { currentUserPost in
                if currentUserPost.ownerUid == post.ownerUid {
                    belongsTuUser = true
                }
                completion(belongsTuUser)
            }
        }
    }
    
    static func deletePost(post: Post) {
        guard let currentUseruid = Auth.auth().currentUser?.uid else {return}
        let directoryName = FireStoreDirectory.posts
        
        API.collectionPosts.document(post.postId).delete()
        API.collectionUsers.document(currentUseruid).collection(Resources.userFeed).document(post.postId).delete()
        ImageService.deleteImage(withUid: post.imageUid, directory: directoryName) { error in
            if let error = error {
                print("error while deleting image \(error.localizedDescription)")
            } 
        }

        UserService.fetchFollowers(forUid: currentUseruid) { followers in
            followers.forEach { follower in
                API.collectionUsers.document(follower.uid).collection(Resources.userFeed).document(post.postId).delete()
            }
        }
    }
}
