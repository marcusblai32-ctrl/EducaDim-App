from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import (
    admin_views,
    certificate_views,
    chat_views,
    notification_views,
    progress_views,
    quiz_views,
    views,
)

app_name = "mobile_api"

urlpatterns = [
    # --- Otantifikasyon JWT ---
    path("auth/login/", views.LoginView.as_view(), name="login"),
    path("auth/token/refresh/", TokenRefreshView.as_view(), name="token_refresh"),

    # --- Kont itilizatè ---
    path("me/", views.MeView.as_view(), name="me"),

    # --- Kou ---
    path("courses/", views.CourseListView.as_view(), name="course_list"),
    path("courses/<int:pk>/", views.CourseDetailView.as_view(), name="course_detail"),
    path("courses/<int:pk>/access/", views.CourseAccessView.as_view(), name="course_access"),
    path(
        "courses/<int:pk>/curriculum/",
        views.CourseCurriculumView.as_view(),
        name="course_curriculum",
    ),
    path(
        "lessons/<int:pk>/",
        views.LessonDetailView.as_view(),
        name="lesson_detail",
    ),

    # --- Pwogrè + flashcards (adisyon) ---
    path(
        "lessons/<int:pk>/complete/",
        progress_views.LessonCompleteView.as_view(),
        name="lesson_complete",
    ),
    path("me/progress/", progress_views.MyProgressView.as_view(), name="me_progress"),
    path("me/activity/", progress_views.MyActivityView.as_view(), name="me_activity"),
    path(
        "courses/<int:pk>/flashcards/",
        progress_views.CourseFlashcardsView.as_view(),
        name="course_flashcards",
    ),

    # --- Notifikasyon (adisyon) ---
    path(
        "notifications/",
        notification_views.NotificationListView.as_view(),
        name="notification_list",
    ),
    path(
        "notifications/unread-count/",
        notification_views.NotificationUnreadCountView.as_view(),
        name="notification_unread_count",
    ),
    path(
        "notifications/read-all/",
        notification_views.NotificationReadAllView.as_view(),
        name="notification_read_all",
    ),
    path(
        "notifications/<int:pk>/read/",
        notification_views.NotificationReadView.as_view(),
        name="notification_read",
    ),

    # --- Quiz (adisyon) ---
    path(
        "courses/<int:pk>/quizzes/",
        quiz_views.CourseQuizzesView.as_view(),
        name="course_quizzes",
    ),
    path("quizzes/<int:pk>/", quiz_views.QuizDetailView.as_view(), name="quiz_detail"),
    path("quizzes/<int:pk>/start/", quiz_views.QuizStartView.as_view(), name="quiz_start"),
    path(
        "quiz-attempts/<int:pk>/submit/",
        quiz_views.QuizAttemptSubmitView.as_view(),
        name="quiz_attempt_submit",
    ),
    path(
        "quiz-attempts/<int:pk>/",
        quiz_views.QuizAttemptDetailView.as_view(),
        name="quiz_attempt_detail",
    ),

    # --- Chat ---
    path("chat/rooms/", chat_views.RoomListView.as_view(), name="chat_rooms"),
    path(
        "chat/rooms/group/<int:course_id>/",
        chat_views.GroupRoomView.as_view(),
        name="chat_group_room",
    ),
    path(
        "chat/rooms/<int:pk>/messages/",
        chat_views.RoomMessagesView.as_view(),
        name="chat_messages",
    ),
    # --- Sètifika ---
    path("certificates/", certificate_views.MyCertificatesView.as_view(), name="certificates"),
    # --- Administrasyon kontni (admin/staff) ---
    path("admin/capabilities/", admin_views.CapabilitiesView.as_view(), name="admin_capabilities"),
    path("admin/meta/", admin_views.MetaView.as_view(), name="admin_meta"),
    path("admin/courses/", admin_views.AdminCourseListView.as_view(), name="admin_courses"),
    path(
        "admin/courses/<int:pk>/",
        admin_views.AdminCourseDetailView.as_view(),
        name="admin_course_detail",
    ),
    path(
        "admin/courses/<int:pk>/tree/",
        admin_views.AdminCourseTreeView.as_view(),
        name="admin_course_tree",
    ),
    path(
        "admin/courses/<int:pk>/unites/",
        admin_views.UniteCreateView.as_view(),
        name="admin_unite_create",
    ),
    path(
        "admin/unites/<int:pk>/modules/",
        admin_views.ModuleCreateView.as_view(),
        name="admin_module_create",
    ),
    path(
        "admin/modules/<int:pk>/lecons/",
        admin_views.LeconCreateView.as_view(),
        name="admin_lecon_create",
    ),
    path(
        "admin/lecons/<int:pk>/sections/",
        admin_views.SectionCreateView.as_view(),
        name="admin_section_create",
    ),
    path(
        "admin/sections/<int:pk>/contenus/",
        admin_views.ContenuCreateView.as_view(),
        name="admin_contenu_create",
    ),
    path("admin/quizzes/", admin_views.QuizCreateView.as_view(), name="admin_quiz_create"),
    path(
        "admin/quizzes/<int:pk>/",
        admin_views.QuizDetailAdminView.as_view(),
        name="admin_quiz_detail",
    ),
    path(
        "admin/quizzes/<int:pk>/questions/",
        admin_views.QuestionCreateView.as_view(),
        name="admin_question_create",
    ),
]
