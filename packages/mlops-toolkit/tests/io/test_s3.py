"""Tests for S3 helpers, mocking boto3 rather than touching real AWS."""

from datetime import UTC, datetime
import json
from unittest.mock import MagicMock, patch

import pytest

from mlops_toolkit.io.s3 import get_dataset_metadata, save_feature_metadata, wait_for_s3_object


@patch("mlops_toolkit.io.s3.boto3.client")
def test_wait_for_s3_object_returns_true_when_object_exists(mock_client):
    s3 = MagicMock()
    mock_client.return_value = s3
    s3.head_object.return_value = {}

    assert wait_for_s3_object("bucket", "key") is True
    s3.head_object.assert_called_once_with(Bucket="bucket", Key="key")


@patch("mlops_toolkit.io.s3.time.sleep", return_value=None)
@patch("mlops_toolkit.io.s3.boto3.client")
def test_wait_for_s3_object_times_out(mock_client, mock_sleep):
    s3 = MagicMock()
    mock_client.return_value = s3
    s3.exceptions.ClientError = Exception
    s3.head_object.side_effect = Exception("not found")

    with pytest.raises(TimeoutError):
        wait_for_s3_object("bucket", "key", timeout=2)


@patch("mlops_toolkit.io.s3.boto3.client")
def test_get_dataset_metadata_parses_latest_version(mock_client):
    s3 = MagicMock()
    mock_client.return_value = s3
    s3.list_object_versions.return_value = {
        "Versions": [
            {
                "VersionId": "v123",
                "LastModified": datetime(2026, 1, 1, tzinfo=UTC),
                "Size": 4096,
            }
        ]
    }

    metadata = get_dataset_metadata("s3://my-bucket/path/to/data.parquet")

    assert metadata["source_uri"] == "s3://my-bucket/path/to/data.parquet"
    assert metadata["version_id"] == "v123"
    assert metadata["size_bytes"] == 4096
    s3.list_object_versions.assert_called_once_with(
        Bucket="my-bucket", Prefix="path/to/data.parquet"
    )


@patch("mlops_toolkit.io.s3.boto3.client")
def test_save_feature_metadata_writes_json_alongside_parquet(mock_client):
    s3 = MagicMock()
    mock_client.return_value = s3

    save_feature_metadata({"feature_version": "v1"}, "s3://my-bucket/gold/features.parquet")

    _, kwargs = s3.put_object.call_args
    assert kwargs["Bucket"] == "my-bucket"
    assert kwargs["Key"] == "gold/features_metadata.json"
    assert json.loads(kwargs["Body"]) == {"feature_version": "v1"}
