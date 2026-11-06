from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import notification_views, progress_views, views

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
]
