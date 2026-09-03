from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from traceability.models import Package
from traceability.services.qrcode_service import make_qr_content_file


class Command(BaseCommand):
    help = (
        "Regenerate the QR code image + public_url for already-packaged "
        "batches against the CURRENT settings.PUBLIC_BASE_URL. Both are "
        "baked in once, at packaging time (package_batch mutation), and "
        "never change again on their own -- so a batch packaged before "
        "switching networks (e.g. dev_up.sh --lan against a different "
        "hotspot IP than last time) keeps pointing at the old host forever "
        "until this is run. Safe to re-run any time; regenerating is a "
        "pure function of (batch_id, PUBLIC_BASE_URL), never DB state."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--batch-id",
            help="Only refresh this one batch (e.g. HC-2026-0004). Default: refresh every packaged batch.",
        )

    def handle(self, *args, **options):
        qs = Package.objects.select_related("batch")
        batch_id = options["batch_id"]
        if batch_id:
            qs = qs.filter(batch__batch_id=batch_id)
            if not qs.exists():
                raise CommandError(f"No packaged batch found with batch_id={batch_id!r}")

        count = 0
        for package in qs:
            new_url = f"{settings.PUBLIC_BASE_URL}/trace/{package.batch.batch_id}"
            if package.public_url == new_url:
                continue
            qr_file = make_qr_content_file(new_url, filename=f"{package.batch.batch_id}.png")
            package.qr_code_image.save(qr_file.name, qr_file, save=False)
            package.public_url = new_url
            package.save(update_fields=["public_url", "qr_code_image"])
            count += 1
            self.stdout.write(f"  {package.batch.batch_id} -> {new_url}")

        if count == 0:
            self.stdout.write(self.style.SUCCESS(f"Already up to date with {settings.PUBLIC_BASE_URL} -- nothing to do."))
        else:
            self.stdout.write(self.style.SUCCESS(f"Refreshed {count} package(s) to {settings.PUBLIC_BASE_URL}."))
