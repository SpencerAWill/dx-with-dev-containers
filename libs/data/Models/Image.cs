namespace Data.Models;

public enum ImageStatus
{
    Uploaded,
    Processing,
    Classified,
    Failed
}

public record Image
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string OriginalFileName { get; init; }
    public required string ContentType { get; init; }
    public required string BlobUri { get; init; }
    public ImageStatus Status { get; set; } = ImageStatus.Uploaded;
    public string? ClassificationLabel { get; set; }
    public double? Confidence { get; set; }
    public string? Description { get; set; }
    public DateTime UploadedAt { get; init; } = DateTime.UtcNow;
    public DateTime? ClassifiedAt { get; set; }
}
