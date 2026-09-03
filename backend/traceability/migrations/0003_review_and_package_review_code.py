import django.db.models.deletion
from django.db import migrations, models


def backfill_review_codes(apps, schema_editor):
    """Existing Package rows predate review_code -- give each one a real
    generated value before the field is made unique+non-nullable below.
    A plain import (not apps.get_model) is fine here since
    Package.generate_review_code() doesn't touch the ORM."""
    from traceability.models import Package

    PackageModel = apps.get_model("traceability", "Package")
    for package in PackageModel.objects.filter(review_code=""):
        package.review_code = Package.generate_review_code()
        package.save(update_fields=["review_code"])


class Migration(migrations.Migration):

    dependencies = [
        ('traceability', '0002_apiary_fssai_license_number_apiary_fssai_verified_at_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='Review',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('rating', models.PositiveSmallIntegerField()),
                ('comment', models.TextField(blank=True)),
                ('reviewer_name', models.CharField(blank=True, max_length=100)),
                ('submitted_at', models.DateTimeField(auto_now_add=True)),
                ('batch', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='reviews', to='traceability.honeybatch')),
            ],
            options={
                'ordering': ['-submitted_at'],
            },
        ),
        migrations.AddField(
            model_name='package',
            name='review_code',
            field=models.CharField(blank=True, default='', editable=False, max_length=12),
        ),
        migrations.RunPython(backfill_review_codes, migrations.RunPython.noop),
        migrations.AlterField(
            model_name='package',
            name='review_code',
            field=models.CharField(editable=False, max_length=12, unique=True),
        ),
    ]
