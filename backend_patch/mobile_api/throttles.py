from rest_framework.throttling import AnonRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    """
    Limit pou login mobil (anplis pwoteksyon django-axes ki deja egziste).
    `rate` defini dirèkteman la pou pa bezwen modifye REST_FRAMEWORK nan settings.
    """

    scope = "mobile_login"
    rate = "10/min"
