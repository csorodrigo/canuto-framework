# Embeds Reference

## Notes

```markdown
![[Note Name]]                         Embed full note
![[Note Name#Heading]]                 Embed specific section
![[Note Name#^block-id]]               Embed specific block
```

## Images

```markdown
![[image.png]]                         Full size
![[image.png|300]]                     Width 300px
![[image.png|640x480]]                 Width x Height
```

## External Images

```markdown
![Alt text](https://example.com/image.png)
![Alt text|300](https://example.com/image.png)
```

## Audio

```markdown
![[audio.mp3]]
![[audio.ogg]]
```

## PDFs

```markdown
![[document.pdf]]                      Full document
![[document.pdf#page=3]]               Specific page
![[document.pdf#height=400]]           Custom height
```

## Lists

```markdown
![[Note#^list-id]]
```

The list must include a block identifier on a separate line:

```markdown
- Item 1
- Item 2

^list-id
```

## Search Results

````markdown
```query
tag:#project status:done
```
````
