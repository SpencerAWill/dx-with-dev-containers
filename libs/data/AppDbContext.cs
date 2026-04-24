using Data.Models;
using Microsoft.EntityFrameworkCore;

namespace Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Image> Images => Set<Image>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Image>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.OriginalFileName).HasMaxLength(256);
            entity.Property(e => e.ContentType).HasMaxLength(128);
            entity.Property(e => e.BlobUri).HasMaxLength(1024);
            entity.Property(e => e.ClassificationLabel).HasMaxLength(256);
            entity.Property(e => e.Description).HasMaxLength(1024);
            entity.Property(e => e.Status).HasConversion<string>().HasMaxLength(32);
        });
    }
}
