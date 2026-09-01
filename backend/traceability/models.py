from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class User(AbstractUser):
    """Beekeepers and admins are real accounts. Consumers are always
    anonymous -- there is no consumer model or login."""

    class Role(models.TextChoices):
        BEEKEEPER = "BEEKEEPER", "Beekeeper"
        ADMIN = "ADMIN", "Admin"

    role = models.CharField(max_length=16, choices=Role.choices, default=Role.BEEKEEPER)

    def __str__(self):
        return f"{self.username} ({self.role})"


class Apiary(models.Model):
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="apiaries")
    name = models.CharField(max_length=200)
    # Free-text description only -- no GPS/geolocation tracking in this MVP.
    location_description = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name_plural = "apiaries"

    def __str__(self):
        return self.name


class Hive(models.Model):
    apiary = models.ForeignKey(Apiary, on_delete=models.CASCADE, related_name="hives")
    label = models.CharField(max_length=100)
    hive_type = models.CharField(max_length=50, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["label"]

    def __str__(self):
        return f"{self.label} ({self.apiary.name})"


class HoneyBatch(models.Model):
    class Status(models.TextChoices):
        HARVESTED = "HARVESTED", "Harvested"
        PROCESSED = "PROCESSED", "Processed"
        QUALITY_CHECKED = "QUALITY_CHECKED", "Quality checked"
        PACKAGED = "PACKAGED", "Packaged"

    batch_id = models.CharField(max_length=32, unique=True, editable=False)
    apiary = models.ForeignKey(Apiary, on_delete=models.PROTECT, related_name="batches")
    hives = models.ManyToManyField(Hive, related_name="batches")
    beekeeper = models.ForeignKey(User, on_delete=models.PROTECT, related_name="batches")
    harvest_date = models.DateField()
    quantity_kg = models.DecimalField(max_digits=8, decimal_places=2)
    floral_source = models.CharField(max_length=150)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.HARVESTED)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name_plural = "honey batches"

    def __str__(self):
        return self.batch_id

    @staticmethod
    def generate_batch_id(on=None):
        """Generate the next sequential batch id for the given (or current)
        year, e.g. "HC-2026-0001". Not perfectly race-safe under concurrent
        writers -- acceptable for a single-dev-server MVP; a production
        version would wrap this in a DB-level sequence or SELECT ... FOR UPDATE.
        """
        year = (on or timezone.now()).year
        prefix = f"HC-{year}-"
        last = (
            HoneyBatch.objects.filter(batch_id__startswith=prefix)
            .order_by("-batch_id")
            .values_list("batch_id", flat=True)
            .first()
        )
        next_seq = int(last.split("-")[-1]) + 1 if last else 1
        return f"{prefix}{next_seq:04d}"


class BatchEvent(models.Model):
    """The central chronological record of everything that happens to a
    batch. Every stage transition creates exactly one of these."""

    class EventType(models.TextChoices):
        HARVESTED = "HARVESTED", "Harvested"
        PROCESSED = "PROCESSED", "Processed"
        QUALITY_CHECKED = "QUALITY_CHECKED", "Quality checked"
        PACKAGED = "PACKAGED", "Packaged"

    class ChainStatus(models.TextChoices):
        PENDING = "PENDING", "Pending"
        CONFIRMED = "CONFIRMED", "Confirmed"
        FAILED = "FAILED", "Failed"

    batch = models.ForeignKey(HoneyBatch, on_delete=models.CASCADE, related_name="events")
    event_type = models.CharField(max_length=20, choices=EventType.choices)
    actor = models.ForeignKey(User, on_delete=models.PROTECT, related_name="batch_events")
    timestamp = models.DateTimeField(auto_now_add=True)

    # Stage-specific payload (e.g. {"method": "cold-extraction", "notes": "..."})
    event_data = models.JSONField(default=dict, blank=True)

    # keccak256("0x"+hex) of the canonical {batch_id, event_type, event_data}
    # payload -- computed once in services/hashing.py and used both here and
    # as the on-chain argument, so the two can never drift apart.
    data_hash = models.CharField(max_length=66)

    # Populated after the on-chain transaction is confirmed.
    tx_hash = models.CharField(max_length=66, null=True, blank=True)
    block_number = models.BigIntegerField(null=True, blank=True)
    # Index of this event within the contract's per-batch event array --
    # needed so verifyHash(batchId, index, hash) and the public trace page's
    # live verification always target the right on-chain slot, rather than
    # assuming Postgres row order matches the contract array order.
    chain_event_index = models.PositiveIntegerField(null=True, blank=True)
    chain_status = models.CharField(max_length=10, choices=ChainStatus.choices, default=ChainStatus.PENDING)

    class Meta:
        ordering = ["timestamp"]

    def __str__(self):
        return f"{self.batch.batch_id}:{self.event_type}"


class QualityCheck(models.Model):
    class Result(models.TextChoices):
        PASSED = "PASSED", "Passed"
        FAILED = "FAILED", "Failed"

    batch = models.ForeignKey(HoneyBatch, on_delete=models.CASCADE, related_name="quality_checks")
    reviewed_by = models.ForeignKey(User, on_delete=models.PROTECT, related_name="quality_checks")
    moisture_content = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    purity_notes = models.TextField(blank=True)
    result = models.CharField(max_length=10, choices=Result.choices)
    checked_at = models.DateTimeField(auto_now_add=True)
    linked_event = models.OneToOneField(
        BatchEvent, on_delete=models.SET_NULL, null=True, blank=True, related_name="quality_check"
    )

    class Meta:
        ordering = ["-checked_at"]

    def __str__(self):
        return f"{self.batch.batch_id}: {self.result}"


class Package(models.Model):
    batch = models.OneToOneField(HoneyBatch, on_delete=models.CASCADE, related_name="package")
    package_code = models.CharField(max_length=50, unique=True)
    unit_count = models.PositiveIntegerField(default=1)
    qr_code_image = models.ImageField(upload_to="qr_codes/")
    public_url = models.URLField()
    packaged_by = models.ForeignKey(User, on_delete=models.PROTECT, related_name="packages")
    packaged_at = models.DateTimeField(auto_now_add=True)
    linked_event = models.OneToOneField(
        BatchEvent, on_delete=models.SET_NULL, null=True, blank=True, related_name="package_event"
    )

    def __str__(self):
        return f"Package {self.package_code} for {self.batch.batch_id}"
