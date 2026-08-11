"""S3 helpers a feature pipeline needs around its Gold-layer write.

All three functions were byte-identical (module docstrings aside) between
iris-project's data_processing/check_s3.py + pipelines/feature_pipeline.py
and ml-default-payment-project's copies of the same. Moved here verbatim.
"""

import json
import time

import boto3
from loguru import logger


def wait_for_s3_object(bucket: str, key: str, timeout: int = 10) -> bool:
    """Poll for an S3 object to exist, for read-after-write consistency.

    Raises:
        TimeoutError: if the object isn't visible within `timeout` seconds.
    """
    s3 = boto3.client("s3")
    logger.info(f"Waiting for S3 object s3://{bucket}/{key} to be available...")

    for _ in range(timeout):
        try:
            s3.head_object(Bucket=bucket, Key=key)
            return True
        except s3.exceptions.ClientError:
            time.sleep(1)
    raise TimeoutError(f"S3 object {key} not found after {timeout} seconds.")


def get_dataset_metadata(data_path: str) -> dict:
    """Get metadata for a versioned dataset from S3, for lineage tracking.

    Args:
        data_path: S3 path to the dataset

    Returns:
        Dictionary with source_uri, version_id, last_modified, size_bytes
    """
    bucket = data_path.split("/")[2]
    key = "/".join(data_path.split("/")[3:])
    s3 = boto3.client("s3")

    versions = s3.list_object_versions(Bucket=bucket, Prefix=key)
    latest_version = versions["Versions"][0]  # Assumes latest is first

    metadata: dict[str, str | int] = {
        "source_uri": data_path,
        "version_id": latest_version["VersionId"],
        "last_modified": latest_version["LastModified"].isoformat(),
        "size_bytes": latest_version["Size"],
    }
    return metadata


def save_feature_metadata(
    feature_metadata: dict, output_path: str, metadata_suffix: str = "_metadata.json"
) -> None:
    """Save feature metadata to S3 alongside the feature data.

    Args:
        feature_metadata: Dictionary with feature metadata
        output_path: S3 path where features are saved
        metadata_suffix: Suffix for metadata file, replacing `.parquet`
    """
    metadata_path = output_path.replace(".parquet", metadata_suffix)

    bucket = metadata_path.split("/")[2]
    key = "/".join(metadata_path.split("/")[3:])

    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(feature_metadata, indent=2),
        ContentType="application/json",
    )
    logger.info(f"Feature metadata saved to: {metadata_path}")
