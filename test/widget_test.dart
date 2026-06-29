// NightOwl UB — model unit tests (Supabase шаардахгүй, цэвэр логик)
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/models/post.dart';
import 'package:night_owl_ub/models/comment.dart';
import 'package:night_owl_ub/models/user_profile.dart';

void main() {
  group('Post.fromJson', () {
    test('media_urls массивыг уншина', () {
      final p = Post.fromJson({
        'id': 'p1', 'user_id': 'u1',
        'media_url': 'a.jpg',
        'media_urls': ['a.jpg', 'b.jpg', 'c.jpg'],
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(p.mediaUrls.length, 3);
      expect(p.mediaUrls.first, 'a.jpg');
    });

    test('media_urls хоосон бол media_url-ээс backfill хийнэ', () {
      final p = Post.fromJson({
        'id': 'p2', 'user_id': 'u1',
        'media_url': 'only.jpg',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(p.mediaUrls, ['only.jpg']);
    });

    test('RPC flat keys (author_*)-ийг author болгож уншина', () {
      final p = Post.fromJson({
        'id': 'p3', 'author_id': 'u9',
        'author_username': 'owl', 'author_verified': true,
        'media_url': 'x.jpg',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(p.userId, 'u9');
      expect(p.author?.username, 'owl');
      expect(p.author?.isVerified, true);
    });
  });

  group('Comment.fromJson', () {
    test('parent_id болон is_liked_by_me уншина', () {
      final c = Comment.fromJson({
        'id': 'c1', 'post_id': 'p1', 'user_id': 'u1',
        'body': 'hi', 'parent_id': 'c0',
        'is_liked_by_me': true, 'likes_count': 5,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(c.parentId, 'c0');
      expect(c.isLikedByMe, true);
      expect(c.likesCount, 5);
    });

    test('parent_id байхгүй бол null (top-level)', () {
      final c = Comment.fromJson({
        'id': 'c2', 'post_id': 'p1', 'user_id': 'u1',
        'body': 'top', 'created_at': '2026-01-01T00:00:00Z',
      });
      expect(c.parentId, isNull);
      expect(c.isLikedByMe, false);
    });
  });

  group('UserProfile.fromJson', () {
    test('is_admin уншина', () {
      final u = UserProfile.fromJson({'id': 'u1', 'is_admin': true});
      expect(u.isAdmin, true);
    });
    test('is_admin байхгүй бол false', () {
      final u = UserProfile.fromJson({'id': 'u2'});
      expect(u.isAdmin, false);
    });
  });
}
