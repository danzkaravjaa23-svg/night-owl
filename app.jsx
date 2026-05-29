/* app.jsx — main shell, router, phone bezel, side controls, Tweaks panel */

const SCREENS = [
  // group, id, label, tabKey (which bottom-tab is active), showNav
  { g: 'Onboarding',   id: 'splash',            label: 'Splash',              tab: null },
  { g: 'Onboarding',   id: 'lang-select',       label: 'Language Select',     tab: null },
  { g: 'Onboarding',   id: 'onboarding-1',      label: 'Onboarding · 1/3',    tab: null },
  { g: 'Onboarding',   id: 'onboarding-2',      label: 'Onboarding · 2/3',    tab: null },
  { g: 'Onboarding',   id: 'onboarding-3',      label: 'Onboarding · 3/3',    tab: null },
  { g: 'Onboarding',   id: 'perm-location',     label: 'Perm · Location',     tab: null },
  { g: 'Onboarding',   id: 'perm-notification', label: 'Perm · Notification', tab: null },
  { g: 'Auth',         id: 'auth-landing',      label: 'Auth Landing',        tab: null },
  { g: 'Auth',         id: 'login',             label: 'Login',               tab: null },
  { g: 'Auth',         id: 'register',          label: 'Register',            tab: null },
  { g: 'Auth',         id: 'setup',             label: 'Profile Setup',       tab: null },
  { g: 'Auth',         id: 'forgot-password',   label: 'Forgot Password',     tab: null },
  { g: 'Main',         id: 'feed',              label: 'Feed',                tab: 'feed'  },
  { g: 'Main',         id: 'post-detail',       label: 'Post Detail',         tab: 'feed',  hideNav: true },
  { g: 'Main',         id: 'creator',           label: 'Creator + Paid',      tab: 'feed',  hideNav: true },
  { g: 'Main',         id: 'qpay',              label: 'QPay Payment',        tab: 'feed',  hideNav: true },
  { g: 'Main',         id: 'map',               label: 'Map',                 tab: 'map'   },
  { g: 'Main',         id: 'bar',               label: 'Bar Profile',         tab: 'map',   hideNav: true },
  { g: 'Main',         id: 'post',              label: 'Create Post',         tab: 'post',  hideNav: true },
  { g: 'Main',         id: 'notifications',     label: 'Notifications',       tab: 'notif' },
  { g: 'Main',         id: 'dm-list',           label: 'Chat · List',           tab: null,    hideNav: true },
  { g: 'Main',         id: 'dm-thread',         label: 'Chat · Thread',         tab: null,    hideNav: true },
  { g: 'Main',         id: 'me',                label: 'Profile',             tab: 'me'    },
  { g: 'Main',         id: 'settings',          label: 'Settings',            tab: 'me',    hideNav: true },
  { g: 'Main',         id: 'change-password',   label: 'Change Password',     tab: 'me',    hideNav: true },
  { g: 'Main',         id: 'business',          label: 'Business Dashboard',  tab: 'me',    hideNav: true },
  { g: 'Main',         id: 'affiliate-unlock',  label: 'Affiliate · Unlock',  tab: 'me',    hideNav: true },
  { g: 'Main',         id: 'affiliate',         label: 'Affiliate Program',   tab: 'me',    hideNav: true },
];

const TAB_TO_SCREEN = { feed: 'feed', map: 'map', post: 'post', notif: 'notifications', me: 'me' };

// ─── TRANSLATIONS ───
const TRANSLATIONS = {
  en: {
    // Navigation
    'nav.feed': 'Feed',
    'nav.map': 'Map',
    'nav.create': 'Create',
    'nav.notifications': 'Notifications',
    'nav.profile': 'Profile',

    // Bottom nav tabs
    'tab.feed': 'Feed',
    'tab.map': 'Map',
    'tab.notif': 'Notifications',
    'tab.me': 'Profile',

    // Status
    'status.open': 'Open',
    'status.closed': 'Closed',

    // Error / loading / empty
    'state.error': 'Something went wrong',
    'state.errorBody': 'Please try again',
    'state.retry': 'Retry',
    'state.loading': 'Loading...',

    // Connection
    'err.noConnection': 'Connection Failed',
    'err.checkInternet': 'Please check your internet connection',

    // Onboarding slides
    'onb.1.title': 'Discover the Night Life',
    'onb.1.sub': "UB's hottest bars, lounges and clubs, all in one place.",
    'onb.2.title': 'Watch Live Streams',
    'onb.2.sub': 'Never miss exclusive content from your favorite creators.',
    'onb.3.title': 'Explore on the Map',
    'onb.3.sub': 'Find nearby places and friends, check ratings, and get directions.',

    // Permissions
    'perm.loc.title': 'Share Location?',
    'perm.loc.body': 'We use your location to show nearby bars and lounges on the map. You can change this anytime.',
    'perm.notif.title': 'Allow Notifications?',
    'perm.notif.body': 'Get notified about new content, likes, followers, and events. You can set quiet hours.',

    // Auth
    'auth.tagline': 'The Night Begins',
    'auth.sub': "UB's bar & lounge social",
    'auth.or': 'OR',
    'auth.withGoogle': 'Continue with Google',
    'auth.signIn': 'Sign In',
    'auth.register': 'Register',
    'auth.login': 'Login',
    'auth.username': 'Username',
    'auth.email': 'Email',
    'auth.password': 'Password',
    'auth.confirmPassword': 'Confirm Password',
    'auth.byGoogle': 'Continue with Google',
    'auth.tos': 'Terms of Service',
    'auth.privacy': 'Privacy Policy',
    'auth.agreed': 'Terms of Service and Privacy Policy accepted',
    'auth.profile': 'Set Up Your Profile',

    // Change password
    'pw.current': 'Current Password',
    'pw.new': 'New Password',
    'pw.confirm': 'Confirm New Password',

    // Login
    'login.welcome': 'Welcome back to the night',
    'login.loading': 'Signing in...',
    'login.forgot': 'Forgot password?',
    'login.error': 'Incorrect email or password',
    'login.withGoogle': 'Sign in with Google',
    'login.noAccount': "Don't have an account?",

    // Register
    'reg.sub': 'Create an account and join the club',
    'reg.name': 'Name',
    'reg.tosAgree': 'I have read and agree to the',
    'reg.and': 'and',
    'reg.withGoogle': 'Register with Google',
    'reg.hasAccount': 'Already have an account?',

    // Setup
    'setup.titleLine1': 'Introduce',
    'setup.titleLine2': 'Yourself',
    'setup.sub': 'Add a photo, name, and interests',
    'setup.bio': 'Bio',
    'setup.bioPh': 'I love the nightlife...',
    'setup.interests': 'Interests',

    // Feed
    'feed.empty': 'Feed is Empty',
    'feed.emptyDesc': 'Follow someone or upload your first photo to fill your feed.',
    'feed.uploadImage': 'Upload Photo',
    'feed.likes': 'likes',
    'feed.comment': 'View all comments',
    'feed.featured': 'FEATURED · TONIGHT',

    // Labels
    'lbl.likes': 'likes',
    'lbl.share': 'share',
    'lbl.today': 'TODAY',
    'lbl.newNights': 'new nights',
    'lbl.hoursAgo': 'h ago',
    'lbl.post': 'Post',
    'lbl.follow': 'Follow',
    'lbl.following': 'Following',
    'lbl.posts': 'Posts',
    'lbl.followers': 'Followers',
    'lbl.followingLbl': 'Following',
    'lbl.locked': 'Locked',
    'lbl.comments': 'COMMENTS',
    'lbl.beFirstComment': 'Be the first to comment.',
    'lbl.reply': 'Reply',
    'lbl.notifications': 'Notifications',
    'lbl.today2': 'Today',
    'lbl.thisWeek': 'This Week',
    'lbl.chat': 'Chat',
    'lbl.active': 'ACTIVE',
    'lbl.messages': 'MESSAGES',
    'lbl.online': 'online',
    'lbl.places': 'Places',
    'lbl.people': 'People',
    'lbl.nearby': 'NEARBY',
    'lbl.nearbyPeople': 'NEARBY PEOPLE',
    'lbl.noNearby': 'No nearby places found.',
    'lbl.noNearbyPeople': 'No nearby people found.',
    'lbl.nowAt': 'Now at',
    'lbl.address': 'Address',
    'lbl.phone': 'Phone',
    'lbl.hours': 'Hours',
    'lbl.todaysEvent': "TODAY'S EVENT",
    'lbl.going': 'going',
    'lbl.interested': 'interested',
    'lbl.sendToFriends': 'SEND TO FRIENDS',
    'lbl.sent': 'Sent',
    'lbl.copied': 'Copied',
    'lbl.newPost': 'New Post',
    'lbl.gallery': 'GALLERY',
    'lbl.all': 'All',
    'lbl.caption': 'CAPTION',
    'lbl.addLocation': 'Add Location',
    'lbl.tagPeople': 'Tag People',
    'lbl.addMusic': 'Add Music',
    'lbl.business': 'Business',
    'lbl.last7days': 'LAST 7 DAYS',
    'lbl.views': 'Views',
    'lbl.rating': 'Rating',
    'lbl.viewsChart': 'VIEWS · 7 DAYS',
    'lbl.management': 'MANAGEMENT',
    'lbl.upcomingEvents': 'UPCOMING EVENTS',
    'lbl.settings': 'Settings',
    'lbl.dark': 'Dark',
    'lbl.light': 'Light',
    'lbl.mongol': 'Mongolian',
    'lbl.selectedPhoto': 'Selected photo',

    // Buttons
    'btn.skip': 'Skip',
    'btn.start': 'START',
    'btn.allow': 'Allow',
    'btn.later': 'Not Now',
    'btn.continue': 'Continue',
    'btn.viewAll': 'View All',
    'btn.uploadPhoto': 'Upload Photo',
    'btn.editProfile': 'Edit Profile',
    'btn.shareProfile': 'Share',
    'btn.directions': 'Get Directions',
    'btn.sort': 'Sort',
    'btn.interested': 'Interested',
    'btn.going': 'Going',
    'btn.goingActive': 'Going ✓',
    'btn.more': 'More',
    'btn.copyLink': 'Link',
    'btn.newChat': 'New Chat',
    'btn.post': 'Post',
    'btn.addEvent': 'Add Event',
    'btn.uploadContent': 'Upload Content',
    'btn.viewContent': 'View Content',
    'btn.startWatching': 'Start Watching',
    'btn.publish': 'Publish',

    // Placeholders
    'ph.writeComment': 'Write a comment...',
    'ph.searchPlaces': 'Search bars, lounges',
    'ph.searchPeople': 'Search people',
    'ph.searchChat': 'Search chats',
    'ph.writeMessage': 'Write a message...',
    'ph.caption': 'What happened tonight?...',

    // QPay
    'qpay.payment': 'QPAY · PAYMENT',
    'qpay.waiting': 'Waiting for payment confirmation...',
    'qpay.success': 'Content Unlocked',
    'qpay.failed': 'Payment Failed',
    'qpay.failedBody': 'Insufficient funds or network error.',
    'qpay.selectBank': 'OR SELECT YOUR BANK',
    'qpay.secure': 'Payment securely processed via QPay. Logos to be replaced.',

    // Notifications empty
    'notif.empty.title': 'No Notifications',
    'notif.empty.body': 'New likes, followers, and comments will appear here. Start following someone.',

    // Profile empty
    'profile.empty.title': 'Upload Your First Photo 🦉',
    'profile.empty.body': 'Share your favorite nights and fill your feed.',

    // DM
    'dm.empty.title': 'No Chats',
    'dm.empty.body': 'Receive messages from friends or your favorite venues.',
    'dm.thread.empty.title': 'Start a New Chat',
    'dm.thread.empty.body': 'Send the first message to start the conversation.',
    'lbl.loading.dm': 'Loading messages...',

    // Settings sections
    'sect.account': 'Account',
    'sect.notifications': 'Notifications',
    'sect.privacy': 'Privacy',
    'sect.payments': 'Payments',
    'sect.other': 'Other',

    // Settings items
    'set.editProfile': 'Edit Profile',
    'set.changePassword': 'Change Password',
    'set.language': 'Language',
    'set.appearance': 'Appearance',
    'set.likesComments': 'Likes & Comments',
    'set.newFollowers': 'New Followers',
    'set.eventsInvites': 'Events & Invites',
    'set.privateAccount': 'Private Account',
    'set.activityStatus': 'Show Activity Status',
    'set.qpayHistory': 'QPay History',
    'set.help': 'Help',
    'set.signOut': 'Sign Out',

    // Days
    'day.mon': 'Mon',
    'day.tue': 'Tue',
    'day.wed': 'Wed',
    'day.thu': 'Thu',
    'day.fri': 'Fri',
    'day.sat': 'Sat',
    'day.sun': 'Sun',

    // Months
    'month.may': 'May',
    'month.jun': 'Jun',

    // Event status
    'evt.active': 'Active',
    'evt.draft': 'Draft',

    // Business management rows
    'biz.address': 'Address & Location',
    'biz.hours': 'Working Hours',
    'biz.gallery': 'Photo Gallery',
    'biz.music': 'Music Type',
    'biz.contact': 'Contact',

    // Filter chips
    'filter.all': 'All',
    'filter.open': 'Open',

    // Tweaks
    'tweaks.screen': 'Screen',
    'tweaks.state': 'State',
    'tweaks.feedStyle': 'Feed Style',
    'tweaks.variant': 'Variant',
    'tweaks.brand': 'Brand',
    'tweaks.theme': 'Theme',
    'tweaks.accentColor': 'Accent Palette',
    'tweaks.glow': 'Glow',
    'tweaks.radius': 'Corner Radius',
    'tweaks.font': 'Display Font',
    'tweaks.frame': 'Frame',
    'tweaks.bezel': 'iPhone Bezel',
    'tweaks.meta': 'Screen Meta',
    'tweaks.language': 'Language',

    // UI misc
    'ui.continue': 'Continue',
    'ui.skip': 'Skip',
    'ui.nightOwl': 'Night Owl',
    'ui.follow': 'Follow',
    'ui.unread': 'New notification',
    'ui.empty': 'Empty',
    'ui.loading': 'Loading...',
    'ui.error': 'Error',
    'ui.retry': 'Retry',
    'ui.navHint': '← → to navigate screens',
  },
  mn: {
    // Navigation
    'nav.feed': 'Тэжээл',
    'nav.map': 'Газрын зураг',
    'nav.create': 'Үүсгэх',
    'nav.notifications': 'Мэдэгдэл',
    'nav.profile': 'Профайл',

    // Bottom nav tabs
    'tab.feed': 'Тэжээл',
    'tab.map': 'Газар',
    'tab.notif': 'Мэдэгдэл',
    'tab.me': 'Профайл',

    // Status
    'status.open': 'Нээлттэй',
    'status.closed': 'Хаалттай',

    // Error / loading / empty
    'state.error': 'Алдаа гарлаа',
    'state.errorBody': 'Дахин оролдоно уу',
    'state.retry': 'Дахин оролдох',
    'state.loading': 'Ачаалж байна...',

    // Connection
    'err.noConnection': 'Холболт амжилтгүй',
    'err.checkInternet': 'Интернэт холболтоо шалгана уу',

    // Onboarding slides
    'onb.1.title': 'Шөнийн амьдралыг нээ',
    'onb.1.sub': 'УБ-ын хамгийн халуухан бар, lounge, клубуудыг нэг дор.',
    'onb.2.title': 'Шууд дамжуулалт үз',
    'onb.2.sub': 'Дуртай creator-ийнхээ exclusive контентыг алгасахгүй.',
    'onb.3.title': 'Газрын зураг дээр нээ',
    'onb.3.sub': 'Өөрт ойрхон газар болон найзуудаа олж, үнэлгээг харж, чиглэлээ ав.',

    // Permissions
    'perm.loc.title': 'Байршил хуваалцана уу?',
    'perm.loc.body': 'Ойрхон бар, lounge-уудыг газрын зураг дээр харуулахын тулд бид таны байршлыг ашиглана. Хэзээ ч өөрчилж болно.',
    'perm.notif.title': 'Мэдэгдэл хүлээж авах уу?',
    'perm.notif.body': 'Шинэ контент, лайк, дагагч, эвентийн мэдээллийг танд хүргэе. Чимээгүй цаг тохируулж болно.',

    // Auth
    'auth.tagline': 'Шөнө эхэлж байна',
    'auth.sub': 'УБ-ын бар, lounge-уудын нийгэм',
    'auth.or': 'ЭСВЭЛ',
    'auth.withGoogle': 'Google-ээр үргэлжлүүлэх',
    'auth.signIn': 'Нэвтрэх',
    'auth.register': 'Бүртгүүлэх',
    'auth.login': 'Нэвтрэх',
    'auth.username': 'Хэрэглэгчийн нэр',
    'auth.email': 'И-мэйл',
    'auth.password': 'Нууц үг',
    'auth.confirmPassword': 'Нууц үг баталгаажуулах',
    'auth.byGoogle': 'Google-ээр үргэлжлүүлэх',
    'auth.tos': 'Үйлчилгээний нөхцөл',
    'auth.privacy': 'нууцлалын бодлого',
    'auth.agreed': 'Уйлчилгээний нөхцөл ба нууцлалын бодлого-г уншиж зөвшөөрсөн',
    'auth.profile': 'Өөрийгөө танилцуул',

    // Change password
    'pw.current': 'Одоогийн нууц үг',
    'pw.new': 'Шинэ нууц үг',
    'pw.confirm': 'Шинэ нууц үг давтах',

    // Login
    'login.welcome': 'Шөнийн ертөнцөдөө буцаж тавтай морил',
    'login.loading': 'Нэвтэрч байна...',
    'login.forgot': 'Нууц үг мартсан?',
    'login.error': 'И-мэйл эсвэл нууц үг буруу байна',
    'login.withGoogle': 'Google-ээр нэвтрэх',
    'login.noAccount': 'Бүртгэл байхгүй юу?',

    // Register
    'reg.sub': 'Шинэ хаяг үүсгээд клубт ор',
    'reg.name': 'Нэр',
    'reg.tosAgree': '-г уншиж зөвшөөрсөн',
    'reg.and': 'ба',
    'reg.withGoogle': 'Google-ээр бүртгүүлэх',
    'reg.hasAccount': 'Бүртгэлтэй юу?',

    // Setup
    'setup.titleLine1': 'Өөрийгөө',
    'setup.titleLine2': 'танилцуул',
    'setup.sub': 'Зураг, нэр, сонирхлоо нэм',
    'setup.bio': 'Танилцуулга',
    'setup.bioPh': 'Шөнийн соёлд дуртай. Live music, jazz, vinyl.',
    'setup.interests': 'Сонирхол',

    // Feed
    'feed.empty': 'Тэжээл хоосон байна',
    'feed.emptyDesc': 'Хэн нэгнийг дага эсвэл эхний зургаа оруулаад тэжээлээ дүүргэж эхэл.',
    'feed.uploadImage': 'Зураг оруулах',
    'feed.likes': 'лайк',
    'feed.comment': 'Бүх коммент үзэх',
    'feed.featured': 'ОНЦЛОХ · ӨНӨӨ ШӨНӨ',

    // Labels
    'lbl.likes': 'лайк',
    'lbl.share': 'хуваалцах',
    'lbl.today': 'ӨНӨӨ',
    'lbl.newNights': 'шинэ шөнө',
    'lbl.hoursAgo': 'ц өмнө',
    'lbl.post': 'Нийтлэл',
    'lbl.follow': 'Дагах',
    'lbl.following': 'Дагаж байна',
    'lbl.posts': 'Пост',
    'lbl.followers': 'Дагагч',
    'lbl.followingLbl': 'Дагаж буй',
    'lbl.locked': 'Түгжээтэй',
    'lbl.comments': 'КОММЕНТ',
    'lbl.beFirstComment': 'Хамгийн түрүүнд коммент бичээрэй.',
    'lbl.reply': 'Хариулах',
    'lbl.notifications': 'Мэдэгдэл',
    'lbl.today2': 'Өнөөдөр',
    'lbl.thisWeek': 'Энэ долоо хоног',
    'lbl.chat': 'Чат',
    'lbl.active': 'ИДЭВХТЭЙ',
    'lbl.messages': 'МЕССЕЖ',
    'lbl.online': 'онлайн',
    'lbl.places': 'Газар',
    'lbl.people': 'Хүмүүс',
    'lbl.nearby': 'ОЙРХОН ГАЗАР',
    'lbl.nearbyPeople': 'ОЙРХОН ХҮМҮҮС',
    'lbl.noNearby': 'Ойролцоо газар олдсонгүй.',
    'lbl.noNearbyPeople': 'Ойролцоо хүн олдсонгүй.',
    'lbl.nowAt': 'Одоо',
    'lbl.address': 'Хаяг',
    'lbl.phone': 'Утас',
    'lbl.hours': 'Цаг',
    'lbl.todaysEvent': 'ӨНӨӨДРИЙН ЭВЕНТ',
    'lbl.going': 'ирэх',
    'lbl.interested': 'сонирхсон',
    'lbl.sendToFriends': 'НАЙЗУУДДАА ИЛГЭЭХ',
    'lbl.sent': 'Илгээв',
    'lbl.copied': 'Хуулав',
    'lbl.newPost': 'Шинэ нийтлэл',
    'lbl.gallery': 'ГАЛЕРЕЙ',
    'lbl.all': 'Бүгд',
    'lbl.caption': 'ТАЙЛБАР',
    'lbl.addLocation': 'Байршил нэмэх',
    'lbl.tagPeople': 'Хүмүүс таглах',
    'lbl.addMusic': 'Дуу нэмэх',
    'lbl.business': 'Бизнес',
    'lbl.last7days': 'СҮҮЛИЙН 7 ХОНОГ',
    'lbl.views': 'Үзэлт',
    'lbl.rating': 'Үнэлгээ',
    'lbl.viewsChart': 'ҮЗЭЛТ · 7 ХОНОГ',
    'lbl.management': 'УДИРДЛАГА',
    'lbl.upcomingEvents': 'ИРЭХ ЭВЕНТҮҮД',
    'lbl.settings': 'Тохиргоо',
    'lbl.dark': 'Шөнө',
    'lbl.light': 'Өдөр',
    'lbl.mongol': 'Монгол',
    'lbl.selectedPhoto': 'Сонгосон зураг',

    // Buttons
    'btn.skip': 'Алгасах',
    'btn.start': 'ЭХЛЭХ',
    'btn.allow': 'Зөвшөөрөх',
    'btn.later': 'Дараа нь',
    'btn.continue': 'Үргэлжлүүлэх',
    'btn.viewAll': 'Бүгдийг харах',
    'btn.uploadPhoto': 'Зураг оруулах',
    'btn.editProfile': 'Профайл засах',
    'btn.shareProfile': 'Хуваалцах',
    'btn.directions': 'Чиглэл авах',
    'btn.sort': 'Эрэмбэлэх',
    'btn.interested': 'Сонирхолтой',
    'btn.going': 'Очих',
    'btn.goingActive': 'Очно',
    'btn.more': 'Бусад',
    'btn.copyLink': 'Линк',
    'btn.newChat': 'Шинэ чат',
    'btn.post': 'Нийтлэх',
    'btn.addEvent': 'Эвент нэмэх',
    'btn.uploadContent': 'Контент оруулах',
    'btn.viewContent': 'Контент үзэх',
    'btn.startWatching': 'Үзэж эхлэх',
    'btn.publish': 'Нийтлэх',

    // Placeholders
    'ph.writeComment': 'Коммент бичих...',
    'ph.searchPlaces': 'Bar, lounge хайх',
    'ph.searchPeople': 'Хүн хайх',
    'ph.searchChat': 'Чат хайх',
    'ph.writeMessage': 'Мессеж бичих...',
    'ph.caption': 'Энэ шөнө юу болов?...',

    // QPay
    'qpay.payment': 'QPAY · ТӨЛБӨР',
    'qpay.waiting': 'Төлбөр баталгаажихыг хүлээж байна...',
    'qpay.success': 'Контент нээгдлээ',
    'qpay.failed': 'Төлбөр амжилтгүй',
    'qpay.failedBody': 'Дансанд хүрэлцэхгүй эсвэл сүлжээ салсан.',
    'qpay.selectBank': 'ЭСВЭЛ ДАНСАА СОНГО',
    'qpay.secure': 'Төлбөр аюулгүйгээр QPay-ээр шилжих. Логог дараа нь солих.',

    // Notifications empty
    'notif.empty.title': 'Мэдэгдэл алга',
    'notif.empty.body': 'Шинэ лайк, дагагч, коммент энд харагдана. Хэн нэгнийг дагаад эхлээрэй.',

    // Profile empty
    'profile.empty.title': 'Эхний зургаа оруулаарай 🦉',
    'profile.empty.body': 'Дуртай газраа, дуртай шөнөө хуваалцаад тэжээлээ эхлүүлээрэй.',

    // DM
    'dm.empty.title': 'Чат алга',
    'dm.empty.body': 'Найзаасаа эсвэл дуртай газраасаа мессеж хүлээж аваарай.',
    'dm.thread.empty.title': 'Чат шинээр эхлүүлэх',
    'dm.thread.empty.body': 'Эхний мессежээ илгээж яриаг эхлүүлээрэй.',
    'lbl.loading.dm': 'Мессеж ачаалж байна...',

    // Settings sections
    'sect.account': 'Акаунт',
    'sect.notifications': 'Мэдэгдэл',
    'sect.privacy': 'Нууцлал',
    'sect.payments': 'Төлбөр',
    'sect.other': 'Бусад',

    // Settings items
    'set.editProfile': 'Профайл засах',
    'set.changePassword': 'Нууц үг солих',
    'set.language': 'Хэл',
    'set.appearance': 'Харагдац',
    'set.likesComments': 'Лайк ба коммент',
    'set.newFollowers': 'Шинэ дагагч',
    'set.eventsInvites': 'Эвент ба урилга',
    'set.privateAccount': 'Private account',
    'set.activityStatus': 'Идэвх харагдах эсэх',
    'set.qpayHistory': 'QPay түүх',
    'set.help': 'Тусламж',
    'set.signOut': 'Гарах',

    // Days
    'day.mon': 'Дав',
    'day.tue': 'Мяг',
    'day.wed': 'Лха',
    'day.thu': 'Пүр',
    'day.fri': 'Баа',
    'day.sat': 'Бям',
    'day.sun': 'Ням',

    // Months
    'month.may': 'тав',
    'month.jun': 'зур',

    // Event status
    'evt.active': 'Идэвхтэй',
    'evt.draft': 'Ноорог',

    // Business management rows
    'biz.address': 'Хаяг ба байршил',
    'biz.hours': 'Ажиллах цаг',
    'biz.gallery': 'Зургийн галерей',
    'biz.music': 'Тоглолтын төрөл',
    'biz.contact': 'Холбоо барих',

    // Filter chips
    'filter.all': 'Бүгд',
    'filter.open': 'Нээлттэй',

    // Tweaks
    'tweaks.screen': 'Дэлгэц',
    'tweaks.state': 'Төлөв',
    'tweaks.feedStyle': 'Тэжээлийн стиль',
    'tweaks.variant': 'Төрөл',
    'tweaks.brand': 'Брэнд',
    'tweaks.theme': 'Үзүүлэх хэв',
    'tweaks.accentColor': 'Үндсэн өнгө',
    'tweaks.glow': 'Гэрэл',
    'tweaks.radius': 'Булан',
    'tweaks.font': 'Үзүүлэх фонт',
    'tweaks.frame': 'Фрейм',
    'tweaks.bezel': 'iPhone хүрээ',
    'tweaks.meta': 'Дэлгэцийн мэдээлэл',
    'tweaks.language': 'Хэл',

    // UI misc
    'ui.continue': 'Үргэлжлүүлэх',
    'ui.skip': 'Алгасах',
    'ui.nightOwl': 'Шөнийн шувуухай',
    'ui.follow': 'Дагах',
    'ui.unread': 'Шинэ мэдэгдэл',
    'ui.empty': 'Хоосон',
    'ui.loading': 'Ачаалж байна...',
    'ui.error': 'Алдаа',
    'ui.retry': 'Дахин оролдох',
    'ui.navHint': '← → дарж дэлгэц солих',
  }
};

// Current language — updated synchronously at the top of App render,
// so all child tr() calls see the correct value without threading props.
let __lang = 'en';

function tr(key, lang) {
  const l = lang || __lang;
  return TRANSLATIONS[l]?.[key] || key;
}

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "screenId":            "feed",
  "screenState":         "default",
  "feedVariant":         "magazine",
  "theme":               "dark",
  "accent":              ["#FF4D8D", "#FF7B5C", "#FFB347"],
  "glow":                70,
  "radiusPreset":        "standard",
  "displayFont":         "Nunito",
  "showBezel":           true,
  "showMeta":            false,
  "language":            "en",
  "profileDisplayName":  "Munkh Erdene",
  "profileUsername":     "munkh_ub",
  "profileBio":          "Live music · vinyl · cocktail. UB.\nШинэ газар нээх дуртай.",
  "profileInterests":    ["Bar", "Live music", "Cocktail"]
}/*EDITMODE-END*/;

const FONT_OPTIONS = ['Nunito', 'Magnolia Script', 'Playfair Display', 'Bricolage Grotesque', 'DM Serif Display', 'Space Grotesk'];
const ACCENT_OPTIONS = [
  ['#FF4D8D', '#FF7B5C', '#FFB347'],
  ['#7B2FF7', '#B14CF7', '#FF4D8D'],
  ['#3DD68C', '#5C7BFF', '#7B2FF7'],
  ['#FFB347', '#FF7B5C', '#FF4D8D'],
];
const RADIUS_PRESETS = {
  sharp:    { sm: 6,  md: 10, lg: 14, xl: 20 },
  standard: { sm: 12, md: 16, lg: 22, xl: 28 },
  round:    { sm: 16, md: 22, lg: 30, xl: 38 },
};

// ─── Phone bezel ───
function PhoneBezel({ children, show = true }) {
  const W = 393, H = 852, bezel = 11;
  if (!show) {
    return (
      <div data-phone-bezel style={{
        width: W, height: H, borderRadius: 38, overflow: 'hidden',
        background: '#0B0118',
        boxShadow: '0 30px 80px rgba(0,0,0,0.5)',
        position: 'relative',
      }}>{children}</div>
    );
  }
  return (
    <div data-phone-bezel style={{
      width: W + bezel * 2, height: H + bezel * 2,
      borderRadius: 56,
      background: 'linear-gradient(135deg, #1a1a1a 0%, #050505 100%)',
      padding: bezel,
      boxShadow: `
        0 0 0 1px rgba(255,255,255,0.04),
        0 60px 120px rgba(0,0,0,0.7),
        0 30px 60px rgba(255,77,141,0.06),
        inset 0 0 0 1.5px rgba(255,255,255,0.05)
      `,
      position: 'relative',
    }}>
      <div style={{
        width: W, height: H,
        borderRadius: 44, overflow: 'hidden',
        background: '#0B0118',
        position: 'relative',
      }}>
        {children}
      </div>
    </div>
  );
}

// ─── Screen registry / renderer ───
function renderScreen({ id, go, state, feedVariant, language, profile }) {
  const props = { go, state, language, profile };
  switch (id) {
    case 'splash':            return <ScreenSplash {...props}/>;
    case 'lang-select':       return <ScreenLangSelect {...props}/>;
    case 'onboarding-1':      return <ScreenOnboarding {...props} slide={1}/>;
    case 'onboarding-2':      return <ScreenOnboarding {...props} slide={2}/>;
    case 'onboarding-3':      return <ScreenOnboarding {...props} slide={3}/>;
    case 'perm-location':     return <ScreenPermission {...props} kind="location"/>;
    case 'perm-notification': return <ScreenPermission {...props} kind="notification"/>;
    case 'auth-landing':      return <ScreenAuthLanding {...props}/>;
    case 'login':             return <ScreenLogin {...props}/>;
    case 'register':          return <ScreenRegister {...props}/>;
    case 'setup':             return <ScreenSetup {...props}/>;
    case 'forgot-password':   return <ScreenForgotPassword {...props}/>;
    case 'feed':              return <ScreenFeed {...props} variant={feedVariant}/>;
    case 'post-detail':       return <ScreenPostDetail {...props}/>;
    case 'creator':           return <ScreenCreator {...props}/>;
    case 'qpay':              return <ScreenQPay {...props}/>;
    case 'map':               return <ScreenMap {...props}/>;
    case 'bar':               return <ScreenBar {...props}/>;
    case 'post':              return <ScreenCreate {...props}/>;
    case 'notifications':     return <ScreenNotifications {...props}/>;
    case 'dm-list':           return <ScreenDMList {...props}/>;
    case 'dm-thread':         return <ScreenDMThread {...props}/>;
    case 'me':                return <ScreenProfile {...props}/>;
    case 'settings':          return <ScreenSettings {...props}/>;
    case 'change-password':   return <ScreenChangePassword {...props}/>;
    case 'business':          return <ScreenBusiness {...props}/>;
    case 'affiliate-unlock':  return <ScreenAffiliateUnlock {...props}/>;
    case 'affiliate':         return <ScreenAffiliate {...props}/>;
    default: return <div style={{ padding: 40, color: '#fff' }}>?</div>;
  }
}

// ─── Main App ───
function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [notification, setNotification] = React.useState(null);
  const [notificationList, setNotificationList] = React.useState([]);

  // Sync global language variable so tr() works in all child components
  __lang = t.language || 'en';

  // Expose theme setter for Settings screen + side effects bridge
  React.useEffect(() => {
    window.__setTheme    = (v) => setTweak('theme', v);
    window.__setLanguage = (v) => setTweak('language', v);
    window.__goScreen    = (id) => setTweak('screenId', id);
    window.__setProfile  = (fields) => Object.entries(fields).forEach(([k, v]) => setTweak(k, v));
    window.__showNotification = (message, icon = 'check', duration = 3000, addToList = true) => {
      setNotification({ message, icon, duration });
      if (addToList) {
        setNotificationList(prev => [...prev, {
          id: Date.now(),
          message,
          icon,
          timestamp: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
        }]);
      }
    };
    return () => {
      delete window.__setTheme;
      delete window.__setLanguage;
      delete window.__goScreen;
      delete window.__setProfile;
      delete window.__showNotification;
    };
  }, [setTweak]);

  // Apply accent palette + glow + radii + display font + theme as CSS variables
  React.useEffect(() => {
    const root = document.documentElement;
    root.setAttribute('data-theme', t.theme || 'dark');
    const [s, m, e] = t.accent;
    root.style.setProperty('--accent-start', s);
    root.style.setProperty('--accent-mid',   m);
    root.style.setProperty('--accent-end',   e);
    root.style.setProperty('--accent-grad',
      `linear-gradient(135deg, ${s} 0%, ${m} 50%, ${e} 100%)`);
    root.style.setProperty('--accent-grad-soft',
      `linear-gradient(135deg, ${s}33 0%, ${e}1f 100%)`);
    root.style.setProperty('--shadow-glow',
      `0 0 ${0.32 * t.glow}px ${s}, 0 0 ${0.8 * t.glow}px ${e}26`);

    const r = RADIUS_PRESETS[t.radiusPreset] || RADIUS_PRESETS.standard;
    root.style.setProperty('--r-sm', `${r.sm}px`);
    root.style.setProperty('--r-md', `${r.md}px`);
    root.style.setProperty('--r-lg', `${r.lg}px`);
    root.style.setProperty('--r-xl', `${r.xl}px`);

    root.style.setProperty('--ff-display', `'${t.displayFont}', system-ui, sans-serif`);
    root.style.setProperty('--bloom-opacity', String(t.glow / 100));
  }, [t.accent, t.glow, t.radiusPreset, t.displayFont, t.theme]);

  // Load extra fonts on demand
  React.useEffect(() => {
    const extras = FONT_OPTIONS.filter(f => f !== 'Bricolage Grotesque');
    extras.forEach(f => {
      const id = 'font-' + f.replace(/\s+/g, '-');
      if (document.getElementById(id)) return;
      const link = document.createElement('link');
      link.id = id;
      link.rel = 'stylesheet';
      link.href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(f)}:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500&display=swap`;
      document.head.appendChild(link);
    });
  }, []);

  const go = (id) => {
    if (TAB_TO_SCREEN[id]) id = TAB_TO_SCREEN[id];
    setTweak('screenId', id);
  };

  const current = SCREENS.find(s => s.id === t.screenId) || SCREENS[0];
  const i = SCREENS.findIndex(s => s.id === current.id);
  const showNav = current.tab !== null && !current.hideNav;

  return (
    <>
      <div style={{
        position: 'fixed', inset: 0,
        background: `
          radial-gradient(circle at 20% 20%, rgba(123,47,247,0.12), transparent 30%),
          radial-gradient(circle at 80% 80%, rgba(255,77,141,0.10), transparent 32%),
          #050010
        `,
      }}/>

      <main style={{
        position: 'relative',
        minHeight: '100vh',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '40px 20px',
        gap: 40,
      }}>
        <SideArrow dir="left" disabled={i === 0}
          onClick={() => go(SCREENS[Math.max(0, i - 1)].id)}/>

        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20 }}>
          {t.showMeta && <ScreenLabel index={i + 1} total={SCREENS.length} screen={current}/>}

          <PhoneBezel show={t.showBezel}>
            {renderScreen({
              id: current.id,
              go,
              state: t.screenState,
              feedVariant: t.feedVariant,
              language: t.language,
              profile: {
                displayName: t.profileDisplayName,
                username:    t.profileUsername,
                bio:         t.profileBio,
                interests:   t.profileInterests,
              },
            })}

            {showNav && (
              <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}>
                <BottomNav
                  tab={current.tab}
                  onTab={(k) => go(k)}
                  onCenterPress={() => go('post')}
                  language={t.language}
                />
              </div>
            )}
          </PhoneBezel>

          {t.showMeta && (
            <div style={{
              fontFamily: 'JetBrains Mono, monospace', fontSize: 10,
              letterSpacing: '0.16em', textTransform: 'uppercase',
              color: 'rgba(185,169,212,0.4)',
            }}>
              {tr('ui.navHint')}
            </div>
          )}
        </div>

        <SideArrow dir="right" disabled={i === SCREENS.length - 1}
          onClick={() => go(SCREENS[Math.min(SCREENS.length - 1, i + 1)].id)}/>
      </main>

      <KeyNav onPrev={() => { if (i > 0) go(SCREENS[i - 1].id); }}
              onNext={() => { if (i < SCREENS.length - 1) go(SCREENS[i + 1].id); }}/>

      <TweaksPanel>
        <TweakSection label={tr('tweaks.screen')}/>
        <ScreenJumper screens={SCREENS} value={t.screenId} onChange={(v) => setTweak('screenId', v)}/>
        <TweakRadio label={tr('tweaks.state')}
          value={t.screenState}
          options={['default', 'empty', 'loading', 'error']}
          onChange={(v) => setTweak('screenState', v)}/>

        <TweakSection label={tr('tweaks.feedStyle')}/>
        <TweakRadio label={tr('tweaks.variant')}
          value={t.feedVariant}
          options={['editorial', 'magazine', 'minimal']}
          onChange={(v) => setTweak('feedVariant', v)}/>

        <TweakSection label={tr('tweaks.brand')}/>
        <TweakRadio label={tr('tweaks.theme')}
          value={t.theme}
          options={['dark', 'light']}
          onChange={(v) => setTweak('theme', v)}/>
        <TweakColor label={tr('tweaks.accentColor')}
          value={t.accent}
          options={ACCENT_OPTIONS}
          onChange={(v) => setTweak('accent', v)}/>
        <TweakSlider label={tr('tweaks.glow')}
          value={t.glow} min={0} max={120} unit=""
          onChange={(v) => setTweak('glow', v)}/>
        <TweakRadio label={tr('tweaks.radius')}
          value={t.radiusPreset}
          options={['sharp', 'standard', 'round']}
          onChange={(v) => setTweak('radiusPreset', v)}/>
        <TweakSelect label={tr('tweaks.font')}
          value={t.displayFont}
          options={FONT_OPTIONS}
          onChange={(v) => setTweak('displayFont', v)}/>

        <TweakSection label={tr('tweaks.language')}/>
        <TweakRadio label={tr('tweaks.language')}
          value={t.language}
          options={['en', 'mn']}
          onChange={(v) => setTweak('language', v)}/>

        <TweakSection label={tr('tweaks.frame')}/>
        <TweakToggle label={tr('tweaks.bezel')}
          value={t.showBezel} onChange={(v) => setTweak('showBezel', v)}/>
        <TweakToggle label={tr('tweaks.meta')}
          value={t.showMeta} onChange={(v) => setTweak('showMeta', v)}/>
      </TweaksPanel>

      {notification && (
        <NotificationToast
          message={notification.message}
          icon={notification.icon}
          duration={notification.duration}
          onDismiss={() => setNotification(null)}
        />
      )}

      {notificationList.length > 0 && (
        <NotificationList items={notificationList}/>
      )}
    </>
  );
}

// ─── Screen meta label above phone ───
function ScreenLabel({ index, total, screen }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      fontFamily: 'JetBrains Mono, monospace', fontSize: 10,
      letterSpacing: '0.18em', textTransform: 'uppercase',
      color: 'rgba(185,169,212,0.65)',
    }}>
      <span>{String(index).padStart(2, '0')} / {String(total).padStart(2, '0')}</span>
      <span style={{ opacity: 0.3 }}>·</span>
      <span style={{ color: '#FFB347', fontWeight: 600 }}>{screen.g}</span>
      <span style={{ opacity: 0.3 }}>·</span>
      <span style={{ color: '#fff' }}>{screen.label}</span>
    </div>
  );
}

// ─── Side arrow ───
function SideArrow({ dir, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled} style={{
      width: 52, height: 52, borderRadius: 26,
      background: 'rgba(26,11,46,0.6)',
      border: '1px solid rgba(255,255,255,0.08)',
      backdropFilter: 'blur(20px)',
      color: disabled ? 'rgba(255,255,255,0.2)' : 'rgba(255,255,255,0.85)',
      cursor: disabled ? 'default' : 'pointer',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      opacity: disabled ? 0.5 : 1,
      flexShrink: 0,
    }}>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor"
           strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        {dir === 'left'
          ? <path d="M15 6l-6 6 6 6"/>
          : <path d="M9 6l6 6-6 6"/>}
      </svg>
    </button>
  );
}

// ─── Screen jumper ───
function ScreenJumper({ screens, value, onChange }) {
  const groups = ['Onboarding', 'Auth', 'Main'];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: '8px 0' }}>
      {groups.map(g => (
        <div key={g}>
          <div style={{
            fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
            letterSpacing: '0.14em', textTransform: 'uppercase',
            color: 'rgba(255,255,255,0.4)', marginBottom: 6,
          }}>{g}</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {screens.filter(s => s.g === g).map(s => {
              const on = s.id === value;
              return (
                <button key={s.id} onClick={() => onChange(s.id)}
                  style={{
                    textAlign: 'left',
                    padding: '6px 10px',
                    borderRadius: 8,
                    background: on ? 'rgba(255,77,141,0.18)' : 'transparent',
                    border: on ? '1px solid rgba(255,77,141,0.3)' : '1px solid transparent',
                    color: on ? '#fff' : 'rgba(255,255,255,0.7)',
                    fontSize: 12, fontWeight: on ? 600 : 400,
                    cursor: 'pointer',
                  }}>
                  {s.label}
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── Keyboard navigation ───
function KeyNav({ onPrev, onNext }) {
  React.useEffect(() => {
    const handler = (e) => {
      const tag = (e.target?.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea') return;
      if (e.key === 'ArrowLeft')  onPrev();
      if (e.key === 'ArrowRight') onNext();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onPrev, onNext]);
  return null;
}

// mount
ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
