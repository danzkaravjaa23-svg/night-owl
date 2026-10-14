import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/sculpted_icon.dart';
import 'package:night_owl_ub/features/profile/widgets/profile_header.dart';
import 'package:night_owl_ub/models/user_profile.dart';

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets(
          'Profile preserves identity and actions in $brightness at $width with large text',
          (tester) async {
        AppColors.isDarkMode = brightness == Brightness.dark;
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          AppColors.isDarkMode = true;
        });
        final calls = <String>[];
        final profile = UserProfile(
            id: 'actual-user',
            username: 'actual_username',
            name: 'Actual profile name',
            bio: 'Энэ бол хэрэглэгчийн бодит танилцуулга. '
                'Хэрэглэгчийн мэдээлэл болон профайлын бүх үндсэн үйлдэл хадгалагдана.',
            interests: ['Live Music', 'Clubs', 'Jazz'],
            postsCount: 17,
            followersCount: 2400,
            followingCount: 412);
        var selected = 0;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
                backgroundColor: AppColors.bgBase,
                body: MediaQuery(
                    data: MediaQueryData(
                        size: Size(width, 1000),
                        padding: const EdgeInsets.only(top: 44),
                        textScaler: const TextScaler.linear(1.5)),
                    child: Center(
                        child: SizedBox(
                            width: width > 720 ? 720 : width,
                            child: SingleChildScrollView(
                                child: StatefulBuilder(
                                    builder: (context, setState) =>
                                        Column(children: [
                                          ProfileHeader(
                                              profile: profile,
                                              avatar: const SizedBox(
                                                  width: 96,
                                                  height: 96,
                                                  child: CircleAvatar(
                                                      child: Text('A'))),
                                              onEdit: () => calls.add('edit'),
                                              onShare: () => calls.add('share'),
                                              onEditCover: () =>
                                                  calls.add('cover'),
                                              onSettings: () =>
                                                  calls.add('settings'),
                                              onActions: () =>
                                                  calls.add('actions'),
                                              onFollowers: () =>
                                                  calls.add('followers'),
                                              onFollowing: () =>
                                                  calls.add('following')),
                                          ProfileContentTabs(
                                              selected: selected,
                                              onChanged: (value) => setState(
                                                  () => selected = value)),
                                        ])))))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('@actual_username'), findsOneWidget);
        expect(tester.widget<Text>(find.text('@actual_username')).style?.color,
            AppColors.textSecondary);
        expect(
            tester.widget<Text>(find.text('Actual profile name')).style?.color,
            AppColors.textPrimary);
        expect(tester.getRect(find.text('Actual profile name')).top,
            lessThan(tester.getRect(find.text('@actual_username')).top));
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            AppColors.bgBase);
        // Controls over the cover stay legible in either theme; body controls adapt.
        for (final tooltip in [
          'Тохиргоо',
          'Профайлын үйлдлүүд',
          'Нүүр зураг солих'
        ]) {
          final icon = tester.widget<SculptedIcon>(find.descendant(
              of: find.byTooltip(tooltip),
              matching: find.byType(SculptedIcon)));
          expect(icon.onDark, isTrue);
          expect(icon.color, Colors.white);
        }
        expect(tester.getRect(find.byTooltip('Тохиргоо')).bottom,
            lessThan(tester.getRect(find.byTooltip('Нүүр зураг солих')).top));
        final avatar = tester.getRect(find.byType(CircleAvatar));
        final count = tester.getRect(find.text('17'));
        if (width == 320) {
          // Large text moves the complete counters below the avatar.
          expect(count.top, greaterThan(avatar.bottom));
        } else {
          expect(count.left, greaterThan(avatar.right));
          expect(count.center.dy, inInclusiveRange(avatar.top, avatar.bottom));
        }
        expect(find.text('Actual profile name'), findsOneWidget);
        expect(find.text(profile.bio!), findsOneWidget);
        expect(find.text('17'), findsOneWidget);
        expect(find.text('2.4K'), findsOneWidget);
        expect(find.text('412'), findsOneWidget);
        expect(find.byIcon(Icons.verified), findsNothing);
        final fallback = tester.widgetList<Image>(find.byType(Image)).any(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName ==
                    'assets/images/tonight_city.png');
        expect(fallback, isTrue);
        for (final tooltip in [
          'Тохиргоо',
          'Профайлын үйлдлүүд',
          'Нүүр зураг солих'
        ]) {
          await tester.ensureVisible(find.byTooltip(tooltip));
          await tester.tap(find.byTooltip(tooltip));
        }
        for (final label in [
          'Профайл засах',
          'Хуваалцах',
          'Дагагч',
          'Дагаж буй'
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
        }
        expect(calls, [
          'settings',
          'actions',
          'cover',
          'edit',
          'share',
          'followers',
          'following'
        ]);
        await tester.ensureVisible(find.text('Хадгалсан'));
        await tester.tap(find.text('Хадгалсан'));
        await tester.pumpAndSettle();
        expect(selected, 1);
        await tester.tap(find.text('Бичлэг'));
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final identity in [
    (
      UserProfile(id: 'handle-only', username: ' @actual_username ', name: ' '),
      '@actual_username'
    ),
    (UserProfile(id: 'empty-identity', username: ' ', name: ' '), 'Профайл'),
  ]) {
    testWidgets('profile identity falls back cleanly for ${identity.$1.id}',
        (tester) async {
      await tester.pumpWidget(_identityFixture(identity.$1));
      await tester.pumpAndSettle();
      expect(find.text(identity.$2), findsOneWidget);
      expect(tester.widget<Text>(find.text(identity.$2)).style?.fontSize, 22);
      expect(find.text('@@actual_username'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('long profile identity stays complete at 320px with doubled text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = UserProfile(
        id: 'long-identity',
        name: 'Улаанбаатарын үдшийн хөгжим болон хотын амьдралын тэмдэглэл',
        username: 'night_owl_ub_long_profile_handle',
        bio:
            'Хөгжим, шинэ газрууд болон хотын амьдралын тухай бодит тэмдэглэл.',
        interests: ['Live Music', 'Хотын амьдрал'],
        isVerified: true);
    var coverEdits = 0;
    await tester.pumpWidget(
        _identityFixture(profile, scale: 2, onEditCover: () => coverEdits++));
    await tester.pumpAndSettle();
    expect(find.text(profile.name!), findsOneWidget);
    expect(find.text('@${profile.username}'), findsOneWidget);
    expect(find.text(profile.bio!), findsOneWidget);
    expect(find.byTooltip('Баталгаажсан профайл'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final avatar = tester.getRect(find.byType(CircleAvatar));
    final cover = tester.getRect(find.byType(Image));
    expect(avatar.top, lessThan(cover.bottom));
    expect(avatar.bottom, greaterThan(cover.bottom));
    // The lower part of this target crosses the overlapping cover edge.
    final camera = tester.getRect(find.byTooltip('Нүүр зураг солих'));
    await tester.tapAt(Offset(camera.center.dx, camera.bottom - 2));
    expect(coverEdits, 1);
    await tester.ensureVisible(find.text('Профайл засах'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('verification is shown only for verified profile data',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ProfileHeader(
                    profile: UserProfile(id: 'verified-user', isVerified: true),
                    avatar: const CircleAvatar(),
                    onEdit: () {},
                    onShare: () {},
                    onEditCover: () {},
                    onSettings: () {},
                    onActions: () {},
                    onFollowers: () {},
                    onFollowing: () {})))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Баталгаажсан профайл'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('Story highlights'), findsNothing);
  });
}

Widget _identityFixture(UserProfile profile,
        {double scale = 1, VoidCallback? onEditCover}) =>
    MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(
                    padding: const EdgeInsets.only(top: 44),
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                    child: ProfileHeader(
                        profile: profile,
                        avatar: const CircleAvatar(child: Text('A')),
                        onEdit: () {},
                        onShare: () {},
                        onEditCover: onEditCover ?? () {},
                        onSettings: () {},
                        onActions: () {},
                        onFollowers: () {},
                        onFollowing: () {})))));
