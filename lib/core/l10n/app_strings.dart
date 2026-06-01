/// NightOwl UB — локализаци
/// EN + MN хоёр хэл — app.jsx TRANSLATIONS-с шууд хөрвүүлсэн
class AppStrings {
  final String locale;
  const AppStrings._(this.locale);

  static const AppStrings en = AppStrings._('en');
  static const AppStrings mn = AppStrings._('mn');

  static AppStrings of(String locale) =>
      locale == 'mn' ? mn : en;

  // ─── Navigation ───
  String get navFeed         => _t('Feed', 'Тэжээл');
  String get navMap          => _t('Map', 'Газрын зураг');
  String get navCreate       => _t('Create', 'Үүсгэх');
  String get navNotifications => _t('Notifications', 'Мэдэгдэл');
  String get navProfile      => _t('Profile', 'Профайл');

  // ─── Status ───
  String get statusOpen   => _t('Open', 'Нээлттэй');
  String get statusClosed => _t('Closed', 'Хаалттай');

  // ─── Error / loading ───
  String get stateError    => _t('Something went wrong', 'Алдаа гарлаа');
  String get stateErrorBody => _t('Please try again', 'Дахин оролдоно уу');
  String get stateRetry    => _t('Retry', 'Дахин оролдох');
  String get stateLoading  => _t('Loading...', 'Ачаалж байна...');
  String get noConnection  => _t('Connection Failed', 'Холболт амжилтгүй');
  String get checkInternet => _t('Please check your internet connection', 'Интернэт холболтоо шалгана уу');

  // ─── Onboarding ───
  String get onb1Title => _t('Discover the Night Life', 'Шөнийн амьдралыг нээ');
  String get onb1Sub   => _t("UB's hottest bars, lounges and clubs, all in one place.", 'УБ-ын хамгийн халуухан бар, lounge, клубуудыг нэг дор.');
  String get onb2Title => _t('Watch Live Streams', 'Шууд дамжуулалт үз');
  String get onb2Sub   => _t('Never miss exclusive content from your favorite creators.', 'Дуртай creator-ийнхээ exclusive контентыг алгасахгүй.');
  String get onb3Title => _t('Explore on the Map', 'Газрын зураг дээр нээ');
  String get onb3Sub   => _t('Find nearby places and friends, check ratings, and get directions.', 'Өөрт ойрхон газар болон найзуудаа олж, үнэлгээг харж, чиглэлээ ав.');

  // ─── Permissions ───
  String get permLocTitle   => _t('Share Location?', 'Байршил хуваалцана уу?');
  String get permLocBody    => _t('We use your location to show nearby bars and lounges on the map. You can change this anytime.', 'Ойрхон бар, lounge-уудыг газрын зураг дээр харуулахын тулд бид таны байршлыг ашиглана. Хэзээ ч өөрчилж болно.');
  String get permNotifTitle => _t('Allow Notifications?', 'Мэдэгдэл хүлээж авах уу?');
  String get permNotifBody  => _t('Get notified about new content, likes, followers, and events. You can set quiet hours.', 'Шинэ контент, лайк, дагагч, эвентийн мэдээллийг танд хүргэе. Чимээгүй цаг тохируулж болно.');

  // ─── Auth ───
  String get authTagline    => _t('The Night Begins', 'Шөнө эхэлж байна');
  String get authSub        => _t("UB's bar & lounge social", 'УБ-ын бар, lounge-уудын нийгэм');
  String get authOr         => _t('OR', 'ЭСВЭЛ');
  String get authWithGoogle => _t('Continue with Google', 'Google-ээр үргэлжлүүлэх');
  String get authSignIn     => _t('Sign In', 'Нэвтрэх');
  String get authRegister   => _t('Register', 'Бүртгүүлэх');
  String get authEmail      => _t('Email', 'И-мэйл');
  String get authPassword   => _t('Password', 'Нууц үг');
  String get authConfirmPw  => _t('Confirm Password', 'Нууц үг баталгаажуулах');
  String get authUsername   => _t('Username', 'Хэрэглэгчийн нэр');
  String get authProfile    => _t('Set Up Your Profile', 'Өөрийгөө танилцуул');
  String get authTos        => _t('Terms of Service', 'Үйлчилгээний нөхцөл');
  String get authPrivacy    => _t('Privacy Policy', 'Нууцлалын бодлого');

  // ─── Login ───
  String get loginWelcome   => _t('Welcome back to the night', 'Шөнийн ертөнцөдөө буцаж тавтай морил');
  String get loginLoading   => _t('Signing in...', 'Нэвтэрч байна...');
  String get loginForgot    => _t('Forgot password?', 'Нууц үг мартсан?');
  String get loginError     => _t('Incorrect email or password', 'И-мэйл эсвэл нууц үг буруу байна');
  String get loginNoAccount => _t("Don't have an account?", 'Бүртгэл байхгүй юу?');

  // ─── Register ───
  String get regSub         => _t('Create an account and join the club', 'Шинэ хаяг үүсгээд клубт ор');
  String get regName        => _t('Name', 'Нэр');
  String get regTosAgree    => _t('I have read and agree to the', '-г уншиж зөвшөөрсөн');
  String get regAnd         => _t('and', 'ба');
  String get regHasAccount  => _t('Already have an account?', 'Бүртгэлтэй юу?');

  // ─── Profile setup ───
  String get setupTitle1    => _t('Introduce', 'Өөрийгөө');
  String get setupTitle2    => _t('Yourself', 'танилцуул');
  String get setupSub       => _t('Add a photo, name, and interests', 'Зураг, нэр, сонирхлоо нэм');
  String get setupBio       => _t('Bio', 'Танилцуулга');
  String get setupBioPh     => _t('I love the nightlife...', 'Шөнийн соёлд дуртай. Live music, jazz, vinyl.');
  String get setupInterests => _t('Interests', 'Сонирхол');

  // ─── Feed ───
  String get feedEmpty      => _t('Feed is Empty', 'Тэжээл хоосон байна');
  String get feedEmptyDesc  => _t('Follow someone or upload your first photo to fill your feed.', 'Хэн нэгнийг дага эсвэл эхний зургаа оруулаад тэжээлээ дүүргэж эхэл.');
  String get feedFeatured   => _t('FEATURED · TONIGHT', 'ОНЦЛОХ · ӨНӨӨ ШӨНӨ');

  // ─── Labels ───
  String get lblFollow      => _t('Follow', 'Дагах');
  String get lblFollowing   => _t('Following', 'Дагаж байна');
  String get lblPosts       => _t('Posts', 'Пост');
  String get lblFollowers   => _t('Followers', 'Дагагч');
  String get lblComments    => _t('COMMENTS', 'КОММЕНТ');
  String get lblReply       => _t('Reply', 'Хариулах');
  String get lblNearby      => _t('NEARBY', 'ОЙРХОН ГАЗАР');
  String get lblNearbyPeople => _t('NEARBY PEOPLE', 'ОЙРХОН ХҮМҮҮС');
  String get lblNowAt       => _t('Now at', 'Одоо');
  String get lblAddress     => _t('Address', 'Хаяг');
  String get lblPhone       => _t('Phone', 'Утас');
  String get lblHours       => _t('Hours', 'Цаг');
  String get lblTodaysEvent => _t("TODAY'S EVENT", 'ӨНӨӨДРИЙН ЭВЕНТ');
  String get lblGoing       => _t('going', 'ирэх');
  String get lblInterested  => _t('interested', 'сонирхсон');
  String get lblChat        => _t('Chat', 'Чат');
  String get lblActive      => _t('ACTIVE', 'ИДЭВХТЭЙ');
  String get lblMessages    => _t('MESSAGES', 'МЕССЕЖ');
  String get lblOnline      => _t('online', 'онлайн');
  String get lblViews       => _t('Views', 'Үзэлт');
  String get lblRating      => _t('Rating', 'Үнэлгээ');
  String get lblGallery     => _t('GALLERY', 'ГАЛЕРЕЙ');
  String get lblCaption     => _t('CAPTION', 'ТАЙЛБАР');
  String get lblAddLocation => _t('Add Location', 'Байршил нэмэх');
  String get lblTagPeople   => _t('Tag People', 'Хүмүүс таглах');
  String get lblBusiness    => _t('Business', 'Бизнес');
  String get lblDark        => _t('Dark', 'Шөнө');
  String get lblLight       => _t('Light', 'Өдөр');
  String get lblSettings    => _t('Settings', 'Тохиргоо');

  // ─── Buttons ───
  String get btnSkip        => _t('Skip', 'Алгасах');
  String get btnStart       => _t('START', 'ЭХЛЭХ');
  String get btnAllow       => _t('Allow', 'Зөвшөөрөх');
  String get btnLater       => _t('Not Now', 'Дараа нь');
  String get btnContinue    => _t('Continue', 'Үргэлжлүүлэх');
  String get btnViewAll     => _t('View All', 'Бүгдийг харах');
  String get btnEditProfile => _t('Edit Profile', 'Профайл засах');
  String get btnDirections  => _t('Get Directions', 'Чиглэл авах');
  String get btnGoing       => _t('Going', 'Очих');
  String get btnPost        => _t('Post', 'Нийтлэх');
  String get btnPublish     => _t('Publish', 'Нийтлэх');
  String get btnNewChat     => _t('New Chat', 'Шинэ чат');
  String get btnAddEvent    => _t('Add Event', 'Эвент нэмэх');
  String get btnSignOut     => _t('Sign Out', 'Гарах');

  // ─── Placeholders ───
  String get phWriteComment => _t('Write a comment...', 'Коммент бичих...');
  String get phSearchPlaces => _t('Search bars, lounges', 'Bar, lounge хайх');
  String get phSearchPeople => _t('Search people', 'Хүн хайх');
  String get phWriteMessage => _t('Write a message...', 'Мессеж бичих...');
  String get phCaption      => _t('What happened tonight?...', 'Энэ шөнө юу болов?...');

  // ─── QPay ───
  String get qpayPayment   => _t('QPAY · PAYMENT', 'QPAY · ТӨЛБӨР');
  String get qpayWaiting   => _t('Waiting for payment confirmation...', 'Төлбөр баталгаажихыг хүлээж байна...');
  String get qpaySuccess   => _t('Content Unlocked', 'Контент нээгдлээ');
  String get qpayFailed    => _t('Payment Failed', 'Төлбөр амжилтгүй');
  String get qpaySelectBank => _t('OR SELECT YOUR BANK', 'ЭСВЭЛ ДАНСАА СОНГО');

  // ─── Notifications ───
  String get notifEmptyTitle => _t('No Notifications', 'Мэдэгдэл алга');
  String get notifEmptyBody  => _t('New likes, followers, and comments will appear here.', 'Шинэ лайк, дагагч, коммент энд харагдана.');

  // ─── DM ───
  String get dmEmptyTitle       => _t('No Chats', 'Чат алга');
  String get dmEmptyBody        => _t('Receive messages from friends or your favorite venues.', 'Найзаасаа эсвэл дуртай газраасаа мессеж хүлээж аваарай.');
  String get dmThreadEmptyTitle => _t('Start a New Chat', 'Чат шинээр эхлүүлэх');
  String get dmThreadEmptyBody  => _t('Send the first message to start the conversation.', 'Эхний мессежээ илгээж яриаг эхлүүлээрэй.');

  // ─── Profile ───
  String get profileEmptyTitle => _t('Upload Your First Photo 🦉', 'Эхний зургаа оруулаарай 🦉');
  String get profileEmptyBody  => _t('Share your favorite nights and fill your feed.', 'Дуртай газраа, дуртай шөнөө хуваалцаад тэжээлээ эхлүүлээрэй.');

  // ─── Settings ───
  String get sectAccount        => _t('Account', 'Акаунт');
  String get sectNotifications  => _t('Notifications', 'Мэдэгдэл');
  String get sectPrivacy        => _t('Privacy', 'Нууцлал');
  String get sectPayments       => _t('Payments', 'Төлбөр');
  String get sectOther          => _t('Other', 'Бусад');
  String get setEditProfile     => _t('Edit Profile', 'Профайл засах');
  String get setChangePassword  => _t('Change Password', 'Нууц үг солих');
  String get setLanguage        => _t('Language', 'Хэл');
  String get setAppearance      => _t('Appearance', 'Харагдац');
  String get setPrivateAccount  => _t('Private Account', 'Private account');
  String get setActivityStatus  => _t('Show Activity Status', 'Идэвх харагдах эсэх');
  String get setHelp            => _t('Help', 'Тусламж');
  String get setSignOut         => _t('Sign Out', 'Гарах');

  // ─── Business ───
  String get bizAddress => _t('Address & Location', 'Хаяг ба байршил');
  String get bizHours   => _t('Working Hours', 'Ажиллах цаг');
  String get bizGallery => _t('Photo Gallery', 'Зургийн галерей');
  String get bizMusic   => _t('Music Type', 'Тоглолтын төрөл');
  String get bizContact => _t('Contact', 'Холбоо барих');

  // ─── Filter ───
  String get filterAll  => _t('All', 'Бүгд');
  String get filterOpen => _t('Open', 'Нээлттэй');

  // ─── App name ───
  String get appName    => _t('Night Owl', 'Шөнийн шувуухай');

  // ─── Helper ───
  String _t(String en, String mn) => locale == 'mn' ? mn : en;
}
