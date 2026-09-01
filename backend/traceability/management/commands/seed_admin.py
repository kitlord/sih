from django.core.management.base import BaseCommand, CommandError

from traceability.models import User


class Command(BaseCommand):
    help = (
        "Create an ADMIN user. The public `register` GraphQL mutation can "
        "only ever create BEEKEEPER accounts, so this is the only way to "
        "get an admin into the system."
    )

    def add_arguments(self, parser):
        parser.add_argument("--username", default="admin")
        parser.add_argument("--email", default="admin@honeychain.local")
        parser.add_argument("--password", default="admin12345!")

    def handle(self, *args, **options):
        username = options["username"]
        if User.objects.filter(username=username).exists():
            raise CommandError(f'A user named "{username}" already exists.')
        User.objects.create_user(
            username=username,
            email=options["email"],
            password=options["password"],
            role=User.Role.ADMIN,
            is_staff=True,
        )
        self.stdout.write(self.style.SUCCESS(f'Created admin user "{username}".'))
